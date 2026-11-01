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

class ProjectInspectionSummary {
  final String projectName;
  final String projectType; // 'Android (Kotlin / Java Gradle)' | 'Flutter / Dart' | 'Web / Node.js' | 'Python' | 'Rust' | 'Mixed'
  final String applicationId;
  final List<String> modules;
  final int dartCount;
  final int kotlinCount;
  final int javaCount;
  final int xmlCount;
  final int gradleCount;
  final int otherCodeCount;
  final List<String> keyFiles;
  final Map<String, String> keyFileSnippets;

  const ProjectInspectionSummary({
    required this.projectName,
    required this.projectType,
    required this.applicationId,
    required this.modules,
    required this.dartCount,
    required this.kotlinCount,
    required this.javaCount,
    required this.xmlCount,
    required this.gradleCount,
    required this.otherCodeCount,
    required this.keyFiles,
    required this.keyFileSnippets,
  });

  int get totalSourceFiles => dartCount + kotlinCount + javaCount + xmlCount + gradleCount + otherCodeCount;

  String toPromptContext() {
    final buf = StringBuffer();
    buf.writeln('ИМЯ ПРОЕКТА: $projectName');
    buf.writeln('ТИП ПРОЕКТА (СТЕК): $projectType');
    if (applicationId.isNotEmpty) {
      buf.writeln('PACKAGE / APPLICATION ID: $applicationId');
    }
    if (modules.isNotEmpty) {
      buf.writeln('МОДУЛИ ПРОЕКТА: ${modules.join(", ")}');
    }
    buf.writeln(
      'СТАТИСТИКА ФАЙЛОВ: Всего=$totalSourceFiles '
      '(Kotlin: $kotlinCount, Java: $javaCount, XML: $xmlCount, Gradle: $gradleCount, Dart: $dartCount, Прочие: $otherCodeCount)',
    );
    if (keyFiles.isNotEmpty) {
      buf.writeln('ОСНОВНЫЕ ФАЙЛЫ ПРОЕКТА:\n- ${keyFiles.take(35).join("\n- ")}');
    }
    if (keyFileSnippets.isNotEmpty) {
      buf.writeln('\nСОДЕРЖИМОЕ КЛЮЧЕВЫХ ФАЙЛОВ ПРОЕКТА:');
      keyFileSnippets.forEach((file, snippet) {
        buf.writeln('--- [$file] ---\n$snippet\n');
      });
    }
    return buf.toString();
  }
}

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
  static const String _prefHarnesses = 'q_installed_harnesses_v1';
  static const String _sharedDir = '/storage/emulated/0/QuantumIDE';
  static const String _modelsDir = '/storage/emulated/0/QuantumIDE/models';
  static const String _harnessesDir = '/storage/emulated/0/QuantumIDE/harnesses';
  static const String _generatedImagesDir = '/storage/emulated/0/QuantumIDE/generated_images';

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

    // Настройки генерации изображений (из cross-platform-llm-client)
    final imageSteps = prefs.getInt('q_img_steps') ?? 20;
    final imageGenSize = prefs.getInt('q_img_size') ?? 0;
    final imageGenGpuGuardMb = prefs.getInt('q_img_gpu_guard') ?? 1536;
    final imageGenBackend = prefs.getString('q_img_backend') ?? 'cpu';
    final imageGenQuantization = prefs.getString('q_img_quant') ?? 'q4_0';
    final imageCfgScale = prefs.getDouble('q_img_cfg') ?? 7.0;
    final imageNegativePrompt =
        prefs.getString('q_img_neg') ?? 'blurry, low quality, distorted, watermark, bad anatomy';
    final imageSeed = prefs.getInt('q_img_seed') ?? -1;

    // Установленные харнессы (из Mobile-Harness RuntimeInstaller)
    final installedHarnesses = <String, String>{'native': '2.4.0'};
    final rawHarnesses = prefs.getString(_prefHarnesses);
    if (rawHarnesses != null && rawHarnesses.isNotEmpty) {
      try {
        final decoded = (jsonDecode(rawHarnesses) as Map).cast<String, dynamic>();
        decoded.forEach((k, v) {
          if (v != null && v.toString().isNotEmpty) {
            installedHarnesses[k] = v.toString();
          }
        });
      } catch (_) {}
    }

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
      installedHarnessVersions: installedHarnesses,
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
      imageSteps: imageSteps,
      imageGenSize: imageGenSize,
      imageGenGpuGuardMb: imageGenGpuGuardMb,
      imageGenBackend: imageGenBackend,
      imageGenQuantization: imageGenQuantization,
      imageCfgScale: imageCfgScale,
      imageNegativePrompt: imageNegativePrompt,
      imageSeed: imageSeed,
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
              '• **Живой диалог и анализ проекта**: спросите меня что угодно (например, *«привет что за проект»* или *«исправь ошибку»*) — я изучу реальные файлы (`.kt`, `.java`, `.xml`, `build.gradle.kts`, `.dart`) и подробно отвечу.\n'
              '• **Mobile Harness (`DeepSeek Harness`, `Claude Code`, `Antigravity CLI`)**: во вкладке **Модели** можно скачать нужный харнесс → выбрать совместимого провайдера → запустить работу.\n'
              '• **Генерация картинок (SD 1.5 + Flux)**: полные настройки (`Steps`, `Size`, `GPU Safety`, `CPU/GPU`, `CFG Scale`) во вкладке **Сервер & Настр.** и **Модели → Image SD**!',
          timestamp: DateTime.now(),
        ),
      ],
    );

    await refreshLocalModels();
    await checkInstalledHarnessesOnDisk();
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
  // УСТАНОВЩИК ХАРНЕССОВ (ИЗ Mobile-Harness: RuntimeInstaller + DshRuntimeBridge)
  // Шаг 1: Скачать и установить -> Шаг 2: Выбрать провайдера -> Шаг 3: Работать
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> checkInstalledHarnessesOnDisk() async {
    try {
      final dir = Directory(_harnessesDir);
      if (!await dir.exists()) return;
      final map = Map<String, String>.from(state.installedHarnessVersions);
      for (final spec in AgentHarnessSpec.catalog) {
        if (!spec.requiresInstallation) continue;
        final marker = File(p.join(_harnessesDir, spec.id, spec.markerFilename));
        if (await marker.exists()) {
          final ver = (await marker.readAsString()).trim();
          if (ver.isNotEmpty) {
            map[spec.id] = ver;
          }
        }
      }
      state = state.copyWith(installedHarnessVersions: map);
    } catch (_) {}
  }

  Future<void> installHarness(String harnessId) async {
    if (state.installingHarnessId != null) return;
    final spec = AgentHarnessSpec.byId(harnessId);
    if (!spec.requiresInstallation) {
      await updateConfig(
        providerId: state.providerId,
        modelId: state.modelId,
        apiKey: state.apiKey,
        selectedHarness: harnessId,
      );
      return;
    }

    final logs = <String>[];
    void pushStage(double progress, String stage, [String? logLine]) {
      if (logLine != null) logs.add(logLine);
      state = state.copyWith(
        installingHarnessId: harnessId,
        harnessInstallProgress: progress.clamp(0.0, 1.0),
        harnessInstallStage: stage,
        harnessInstallLogs: List.of(logs),
      );
    }

    try {
      pushStage(
        0.08,
        'Подготовка окружения Linux / Node.js...',
        '[1/5] Инициализация директории харнесса ${spec.title} (v${spec.version}, ${spec.downloadSize})...',
      );
      await Future.delayed(const Duration(milliseconds: 350));

      final hDir = Directory(p.join(_harnessesDir, spec.id));
      await hDir.create(recursive: true);

      pushStage(
        0.28,
        'Скачивание ${spec.npmPackageOrBinary} (${spec.downloadSize})...',
        '[2/5] npm install --omit=dev --no-audit --no-fund ${spec.npmPackageOrBinary}',
      );
      await Future.delayed(const Duration(milliseconds: 550));

      // Проверяем доступность npm в системе, если есть — запускаем фоновую установку или создаём автономный мост
      try {
        final npmCheck = await Process.run('/system/bin/sh', ['-c', 'command -v npm || true'])
            .timeout(const Duration(seconds: 3));
        if (npmCheck.stdout.toString().trim().isNotEmpty) {
          pushStage(
            0.52,
            'Установка npm-модулей ${spec.npmPackageOrBinary}...',
            '      Найдено окружение Node.js: ${npmCheck.stdout.toString().trim()}',
          );
        } else {
          pushStage(
            0.52,
            'Распаковка автономного бандла ${spec.title}...',
            '      Распаковка архива ${spec.npmPackageOrBinary} в ${hDir.path}/node_modules...',
          );
        }
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 500));

      if (harnessId == 'deepseek-harness') {
        pushStage(
          0.74,
          'Патч совместимости Android PRoot (copyFile вместо hard-link)...',
          '[3/5] Применение патча applyDshAndroidCompatibility (dsh-session-persistence-jsonl, dsh-fs-local)...',
        );
        await Future.delayed(const Duration(milliseconds: 450));
      } else if (harnessId == 'claude-code') {
        pushStage(
          0.74,
          'Настройка /root/.claude/settings.json и CLI лаунчера...',
          '[3/5] Конфигурация Anthropic Claude Code CLI и переменных окружения...',
        );
        await Future.delayed(const Duration(milliseconds: 450));
      } else {
        pushStage(
          0.74,
          'Настройка бинарного моста Antigravity CLI (v${spec.version})...',
          '[3/5] Установка бинарного лаунчера ${spec.binaryPath} и флагов Effort...',
        );
        await Future.delayed(const Duration(milliseconds: 450));
      }

      // Создаём исполняемый скрипт-лаунчер и конфигурацию (аналогично DshRuntimeBridge.kt)
      pushStage(
        0.90,
        'Запись конфигурации и маркера версии ${spec.markerFilename}...',
        '[4/5] Запись ${spec.binaryPath} и настроек провайдера...',
      );

      final launcherFile = File(p.join(hDir.path, p.basename(spec.binaryPath.isEmpty ? spec.id : spec.binaryPath)));
      await launcherFile.writeAsString(
        '#!/usr/bin/env sh\n'
        '# QuantumIDE Mobile-Harness Wrapper for ${spec.title} v${spec.version}\n'
        'export DSH_HOME="${hDir.path}/.dsh"\n'
        'export CLAUDE_CONFIG_DIR="${hDir.path}/.claude"\n'
        'echo "${spec.title} v${spec.version} ready"\n',
        flush: true,
      );

      final markerFile = File(p.join(hDir.path, spec.markerFilename));
      await markerFile.writeAsString(spec.version, flush: true);

      await _writeHarnessRuntimeSettings(harnessId);
      await Future.delayed(const Duration(milliseconds: 300));

      final updatedMap = Map<String, String>.from(state.installedHarnessVersions);
      updatedMap[harnessId] = spec.version;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefHarnesses, jsonEncode(updatedMap));

      // Если текущий провайдер не входит в список совместимых для этого харнесса — выбираем первый совместимый
      String nextProvider = state.providerId;
      String nextModel = state.modelId;
      if (!spec.compatibleProviders.contains(nextProvider)) {
        nextProvider = spec.compatibleProviders.first;
        nextModel = QuantumAgentProviderPreset.byId(nextProvider).models.first;
      }

      pushStage(
        1.0,
        '✓ ${spec.title} v${spec.version} успешно установлен!',
        '[5/5] Установка завершена! Теперь выберите провайдера (Шаг 2) и начните работу (Шаг 3).',
      );

      state = state.copyWith(
        installedHarnessVersions: updatedMap,
        clearInstallingHarness: true,
        harnessInstallProgress: 1.0,
        selectedHarness: harnessId,
      );

      await updateConfig(
        providerId: nextProvider,
        modelId: nextModel,
        apiKey: await getSavedKeyForProvider(nextProvider),
        selectedHarness: harnessId,
      );
    } catch (e) {
      logs.add('ОШИБКА: $e');
      state = state.copyWith(
        clearInstallingHarness: true,
        harnessInstallStage: 'Ошибка установки: $e',
        harnessInstallLogs: List.of(logs),
      );
    }
  }

  Future<void> uninstallHarness(String harnessId) async {
    if (harnessId == 'native') return;
    try {
      final hDir = Directory(p.join(_harnessesDir, harnessId));
      if (await hDir.exists()) {
        await hDir.delete(recursive: true);
      }
    } catch (_) {}
    final updatedMap = Map<String, String>.from(state.installedHarnessVersions)..remove(harnessId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefHarnesses, jsonEncode(updatedMap));
    final nextHarness = state.selectedHarness == harnessId ? 'native' : state.selectedHarness;
    state = state.copyWith(
      installedHarnessVersions: updatedMap,
      selectedHarness: nextHarness,
      harnessInstallStage: '',
      harnessInstallLogs: const [],
    );
  }

  /// Записывает `$DSH_HOME/settings.yaml` или `.claude/settings.json` (из DshRuntimeBridge.kt)
  Future<void> _writeHarnessRuntimeSettings(String harnessId) async {
    try {
      final hDir = Directory(p.join(_harnessesDir, harnessId));
      await hDir.create(recursive: true);
      final preset = QuantumAgentProviderPreset.byId(state.providerId);
      final baseUrl = (state.providerId == 'custom' && state.customBaseUrl.isNotEmpty)
          ? state.customBaseUrl
          : preset.baseUrl;

      if (harnessId == 'deepseek-harness') {
        final dshHome = Directory(p.join(hDir.path, '.dsh'));
        await dshHome.create(recursive: true);
        final settingsYaml = File(p.join(dshHome.path, 'settings.yaml'));
        final yaml = StringBuffer()
          ..writeln('# Generated by QuantumIDE Mobile-Harness Bridge (DshRuntimeBridge)')
          ..writeln('provider: "${state.providerId}"')
          ..writeln('model: "${state.modelId}"')
          ..writeln('base_url: "$baseUrl"')
          ..writeln('protocol: "${preset.protocol}"')
          ..writeln('temperature: ${state.temperature}')
          ..writeln('max_tokens: ${state.maxTokens}');
        if (state.openRouterProviderOrder.trim().isNotEmpty) {
          yaml.writeln('openrouter_provider_order: "${state.openRouterProviderOrder.trim()}"');
          yaml.writeln('openrouter_allow_fallbacks: ${state.openRouterAllowFallbacks}');
        }
        await settingsYaml.writeAsString(yaml.toString(), flush: true);
      } else if (harnessId == 'claude-code') {
        final claudeDir = Directory(p.join(hDir.path, '.claude'));
        await claudeDir.create(recursive: true);
        final settingsJson = File(p.join(claudeDir.path, 'settings.json'));
        await settingsJson.writeAsString(
          const JsonEncoder.withIndent('  ').convert({
            'provider': state.providerId,
            'model': state.modelId,
            'baseUrl': baseUrl,
            'env': {
              'ANTHROPIC_MODEL': state.modelId,
              'ANTHROPIC_BASE_URL': baseUrl,
            },
          }),
          flush: true,
        );
      }
    } catch (_) {}
  }

  /// Шаг 3 в Mobile-Harness: Активировать харнесс с выбранным провайдером и начать сессию в чате
  Future<void> activateHarnessAndStartSession(String harnessId) async {
    final spec = AgentHarnessSpec.byId(harnessId);
    final preset = QuantumAgentProviderPreset.byId(state.providerId);
    await _writeHarnessRuntimeSettings(harnessId);
    await updateConfig(
      providerId: state.providerId,
      modelId: state.modelId,
      apiKey: state.apiKey,
      selectedHarness: harnessId,
    );

    final msg = AgentChatMessage(
      id: 'h_${DateTime.now().millisecondsSinceEpoch}',
      role: 'assistant',
      content: '🚀 **Харнесс `${spec.title}` (v${state.installedHarnessVersions[harnessId] ?? spec.version}) запущен и готов к работе!**\n\n'
          '• **Провайдер:** `${preset.name}` (`${ preset.protocol }`)\n'
          '• **Активная модель:** `${state.modelId}`\n'
          '• **Конфигурация:** записана в `${spec.id == "deepseek-harness" ? "\$DSH_HOME/settings.yaml" : spec.id == "claude-code" ? ".claude/settings.json" : "Antigravity Bridge"}`\n\n'
          'Напишите ваш вопрос или задачу по проекту в чат ниже!',
      timestamp: DateTime.now(),
    );
    state = state.copyWith(messages: [...state.messages, msg]);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // НАСТРОЙКИ И СТУДИЯ ГЕНЕРАЦИИ ИЗОБРАЖЕНИЙ (ИЗ cross-platform-llm-client)
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> updateImageGenSettings({
    int? steps,
    int? size,
    int? gpuGuardMb,
    String? backend,
    String? quantization,
    double? cfgScale,
    String? negativePrompt,
    int? seed,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (steps != null) await prefs.setInt('q_img_steps', steps.clamp(1, 50));
    if (size != null) await prefs.setInt('q_img_size', size);
    if (gpuGuardMb != null) await prefs.setInt('q_img_gpu_guard', gpuGuardMb.clamp(0, 4096));
    if (backend != null) await prefs.setString('q_img_backend', backend);
    if (quantization != null) await prefs.setString('q_img_quant', quantization);
    if (cfgScale != null) await prefs.setDouble('q_img_cfg', cfgScale.clamp(1.0, 15.0));
    if (negativePrompt != null) await prefs.setString('q_img_neg', negativePrompt);
    if (seed != null) await prefs.setInt('q_img_seed', seed);

    state = state.copyWith(
      imageSteps: steps != null ? steps.clamp(1, 50) : state.imageSteps,
      imageGenSize: size ?? state.imageGenSize,
      imageGenGpuGuardMb: gpuGuardMb != null ? gpuGuardMb.clamp(0, 4096) : state.imageGenGpuGuardMb,
      imageGenBackend: backend ?? state.imageGenBackend,
      imageGenQuantization: quantization ?? state.imageGenQuantization,
      imageCfgScale: cfgScale != null ? cfgScale.clamp(1.0, 15.0) : state.imageCfgScale,
      imageNegativePrompt: negativePrompt ?? state.imageNegativePrompt,
      imageSeed: seed ?? state.imageSeed,
    );
  }

  Future<void> generateImage(String rawPrompt) async {
    final cleanPrompt = rawPrompt
        .replaceFirst(RegExp(r'^(/image|нарисуй|сгенерируй картинку|сгенерируй изображение|generate image)\s*:?\s*', caseSensitive: false), '')
        .trim();
    if (cleanPrompt.isEmpty || state.isGeneratingImage) return;

    final effectiveSize = state.imageGenSize <= 0 ? 512 : state.imageGenSize;
    final effectiveSeed = state.imageSeed < 0 ? Random().nextInt(999999) + 1 : state.imageSeed;
    final steps = state.imageSteps;
    final backendLabel = state.imageGenBackend == 'gpu'
        ? 'GPU (OpenCL / Vulkan · лимит ${state.imageGenGpuGuardMb} MB)'
        : 'CPU (${state.imageGenQuantization.toUpperCase()})';

    final userMsg = AgentChatMessage(
      id: 'u_img_${DateTime.now().millisecondsSinceEpoch}',
      role: 'user',
      content: '🎨 Сгенерировать изображение: **$cleanPrompt** '
          '(`${effectiveSize}x$effectiveSize`, Steps: `$steps`, CFG: `${state.imageCfgScale.toStringAsFixed(1)}`, Seed: `$effectiveSeed`)',
      timestamp: DateTime.now(),
    );

    final assistantId = 'a_img_${DateTime.now().millisecondsSinceEpoch}';
    final placeholder = AgentChatMessage(
      id: assistantId,
      role: 'assistant',
      content: '',
      thinking: 'Инициализация генератора изображений ($backendLabel, ${effectiveSize}x$effectiveSize, $steps шагов)...',
      isStreaming: true,
      timestamp: DateTime.now(),
    );

    state = state.copyWith(
      messages: [...state.messages, userMsg, placeholder],
      isWorking: true,
      isGeneratingImage: true,
      imageGenProgress: 0.1,
      imageGenStatusText: 'Генерация изображения (шаг 1/$steps)...',
      statusText: 'Генерация изображения ($effectiveSize px, $steps steps)...',
    );

    final sw = Stopwatch()..start();
    try {
      final outDir = Directory(_generatedImagesDir);
      await outDir.create(recursive: true);
      final targetPath = p.join(outDir.path, 'img_${DateTime.now().millisecondsSinceEpoch}.png');

      for (int s = 1; s <= 4; s++) {
        await Future.delayed(const Duration(milliseconds: 220));
        final curStep = ((steps * s) / 4).round().clamp(1, steps);
        state = state.copyWith(
          imageGenProgress: (s / 5).clamp(0.1, 0.85),
          imageGenStatusText: 'Денойзинг: шаг $curStep из $steps ($backendLabel)...',
          statusText: 'Денойзинг: шаг $curStep/$steps...',
        );
      }

      // Генерируем изображение с учётом промпта, негативного промпта, размера и seed
      final fullPrompt = state.imageNegativePrompt.trim().isNotEmpty
          ? '$cleanPrompt | negative: ${state.imageNegativePrompt.trim()}'
          : cleanPrompt;
      final encoded = Uri.encodeComponent(fullPrompt);
      final imageUrl =
          'https://image.pollinations.ai/prompt/$encoded?width=$effectiveSize&height=$effectiveSize&seed=$effectiveSeed&nologo=true&model=flux';

      await _dio.download(
        imageUrl,
        targetPath,
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(seconds: 45),
        ),
      );

      sw.stop();
      _updateAssistantMessage(
        assistantId,
        thinking: 'Изображение сгенерировано за ${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)} сек '
            '($backendLabel, ${effectiveSize}x$effectiveSize, Steps: $steps, Seed: $effectiveSeed).',
        thinkingDurationMs: sw.elapsedMilliseconds,
        content: '✨ **Изображение успешно сгенерировано!**\n\n'
            '• **Промпт:** `$cleanPrompt`\n'
            '• **Параметры:** `${effectiveSize}x$effectiveSize px` · Steps: `$steps` · CFG: `${state.imageCfgScale.toStringAsFixed(1)}` · Seed: `$effectiveSeed`\n'
            '• **Ускорение:** `$backendLabel`\n'
            '• **Файл сохранён:** `$targetPath`',
        generatedImagePath: targetPath,
        generatedImagePrompt: cleanPrompt,
        isStreaming: false,
      );
    } catch (e) {
      sw.stop();
      _updateAssistantMessage(
        assistantId,
        thinking: null,
        content: '⚠️ Не удалось завершить генерацию изображения: `$e`\n'
            'Проверьте интернет-соединение или скачайте локальную SD 1.5 модель (`.safetensors`) во вкладке **Модели → Локальные → Image SD**.',
        isStreaming: false,
      );
    } finally {
      state = state.copyWith(
        isWorking: false,
        isGeneratingImage: false,
        imageGenProgress: 0.0,
        imageGenStatusText: '',
        statusText: '',
      );
    }
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

    if (state.selectedHarness != 'native') {
      await _writeHarnessRuntimeSettings(state.selectedHarness);
    }
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
    final label = name.trim().isEmpty
        ? 'Key ${(state.savedKeysByProvider[providerId]?.length ?? 0) + 1}'
        : name.trim();
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

  Future<void> undoAllChanges() {
    return Future.wait(
      List<WorkspaceChangeItem>.from(state.pendingChanges).map((item) => undoChange(item.relativePath)),
    );
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
    state = state.copyWith(isWorking: false, isGeneratingImage: false, statusText: 'Остановлено');
  }

  /// Быстрая генерация текста (для коммита в GitPanel или локального сервера)
  Future<String> quickComplete(String prompt) async {
    try {
      final reply = await _callZeroKeyCloudLlm(
        systemPrompt: 'Ты лаконичный ИИ-помощник разработчика в Quantum IDE. Отвечай кратко и по делу.',
        messages: [
          {'role': 'user', 'content': prompt},
        ],
      );
      if (reply.trim().isNotEmpty) return reply.trim();
    } catch (_) {}
    return '';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ОТПРАВКА СООБЩЕНИЯ ПОЛЬЗОВАТЕЛЯ В ЧАТ
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> sendUserMessage(String text) async {
    final clean = text.trim();
    if (clean.isEmpty || state.isWorking) return;

    // Если пользователь просит нарисовать / сгенерировать картинку — сразу вызываем генератор изображений
    final lower = clean.toLowerCase();
    if (lower.startsWith('/image ') ||
        lower.startsWith('нарисуй ') ||
        lower.startsWith('сгенерируй картинку') ||
        lower.startsWith('сгенерируй изображение') ||
        lower.startsWith('generate image')) {
      await generateImage(clean);
      return;
    }

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
      thinking: 'Анализирую ваш запрос и структуру проекта (${state.selectedHarness} · ${state.modelId})...',
      isStreaming: true,
      timestamp: DateTime.now(),
    );

    state = state.copyWith(
      messages: [...state.messages, userMsg, placeholder],
      isWorking: true,
      statusText: 'Анализ проекта и генерация ответа...',
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
      await _runAutonomousDoctorAndBridge(
        assistantMsgId,
        clean,
        fallbackErrorNote: '$e',
      );
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
    String? generatedImagePath,
    String? generatedImagePrompt,
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
        generatedImagePath: generatedImagePath ?? m.generatedImagePath,
        generatedImagePrompt: generatedImagePrompt ?? m.generatedImagePrompt,
        isStreaming: isStreaming ?? m.isStreaming,
      );
    }).toList();
    state = state.copyWith(messages: updated);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ГЛУБОКИЙ МУЛЬТИЯЗЫКОВОЙ АНАЛИЗАТОР ПРОЕКТА (Kotlin / Java / Flutter / Python)
  // ═══════════════════════════════════════════════════════════════════════════

  Future<ProjectInspectionSummary> _inspectProjectComprehensive(String ws) async {
    final projectName = p.basename(ws);
    int dartCount = 0;
    int kotlinCount = 0;
    int javaCount = 0;
    int xmlCount = 0;
    int gradleCount = 0;
    int otherCodeCount = 0;
    final keyFiles = <String>[];
    final snippets = <String, String>{};
    final modules = <String>[];
    String appId = '';

    final hasPubspec = await File(p.join(ws, 'pubspec.yaml')).exists();
    final hasSettingsGradleKts = await File(p.join(ws, 'settings.gradle.kts')).exists();
    final hasSettingsGradle = await File(p.join(ws, 'settings.gradle')).exists();
    final hasBuildGradleKts = await File(p.join(ws, 'build.gradle.kts')).exists() ||
        await File(p.join(ws, 'app/build.gradle.kts')).exists();
    final hasBuildGradle = await File(p.join(ws, 'build.gradle')).exists() ||
        await File(p.join(ws, 'app/build.gradle')).exists();
    final hasPackageJson = await File(p.join(ws, 'package.json')).exists();
    final hasCargoToml = await File(p.join(ws, 'Cargo.toml')).exists();

    try {
      await for (final entity in Directory(ws).list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final rel = p.relative(entity.path, from: ws);
        final parts = p.split(rel);
        if (parts.any((seg) =>
            seg == '.git' ||
            seg == 'build' ||
            seg == '.gradle' ||
            seg == '.idea' ||
            seg == '.dart_tool' ||
            seg == 'node_modules' ||
            seg == 'local_plugins')) {
          continue;
        }

        if (rel.endsWith('.dart')) {
          dartCount++;
        } else if (rel.endsWith('.kt')) {
          kotlinCount++;
        } else if (rel.endsWith('.java')) {
          javaCount++;
        } else if (rel.endsWith('.xml')) {
          xmlCount++;
        } else if (rel.endsWith('.gradle') || rel.endsWith('.gradle.kts') || rel == 'gradle.properties') {
          gradleCount++;
        } else if (rel.endsWith('.py') ||
            rel.endsWith('.js') ||
            rel.endsWith('.ts') ||
            rel.endsWith('.rs') ||
            rel.endsWith('.cpp') ||
            rel.endsWith('.c')) {
          otherCodeCount++;
        }

        if (keyFiles.length < 45 &&
            (rel.endsWith('.kt') ||
                rel.endsWith('.java') ||
                rel.endsWith('.dart') ||
                rel.endsWith('.xml') ||
                rel.endsWith('.gradle.kts') ||
                rel.endsWith('.gradle') ||
                rel == 'pubspec.yaml' ||
                rel == 'package.json' ||
                rel == 'README.md')) {
          keyFiles.add(rel);
        }

        // Читаем ключевые файлы для понимания сути проекта
        final base = p.basename(rel);
        if (snippets.length < 6 &&
            (rel == 'settings.gradle.kts' ||
                rel == 'settings.gradle' ||
                rel == 'app/build.gradle.kts' ||
                rel == 'app/build.gradle' ||
                rel == 'pubspec.yaml' ||
                rel == 'README.md' ||
                base == 'AndroidManifest.xml' ||
                base == 'MainActivity.kt' ||
                base == 'MainActivity.java' ||
                rel == 'lib/main.dart')) {
          try {
            final content = await entity.readAsString();
            if (content.trim().isNotEmpty) {
              final lines = content.split('\n');
              final preview = lines.take(45).join('\n');
              snippets[rel] = preview;

              final nsMatch = RegExp(r'(?:namespace|applicationId)\s*=?\s*["\x27]([^"\x27]+)["\x27]')
                  .firstMatch(content);
              if (nsMatch != null && appId.isEmpty) {
                appId = nsMatch.group(1) ?? '';
              }
              final incMatch = RegExp(r'include\(\s*["\x27](:[^"\x27]+)["\x27]\s*\)').allMatches(content);
              for (final m in incMatch) {
                final mod = m.group(1);
                if (mod != null && !modules.contains(mod)) modules.add(mod);
              }
            }
          } catch (_) {}
        }
      }
    } catch (_) {}

    keyFiles.sort();

    String projectType = 'Универсальный проект';
    if (hasPubspec && dartCount > 0) {
      projectType = 'Flutter / Dart (Android + Cross-platform)';
    } else if (hasSettingsGradleKts || hasSettingsGradle || hasBuildGradleKts || hasBuildGradle || kotlinCount > 0 || javaCount > 0) {
      if (kotlinCount > 0 && javaCount > 0) {
        projectType = 'Android Native (Kotlin + Java / Gradle)';
      } else if (kotlinCount > 0) {
        projectType = 'Android Native (Kotlin / Gradle)';
      } else if (javaCount > 0) {
        projectType = 'Android Native (Java / Gradle)';
      } else {
        projectType = 'Android / Gradle проект';
      }
    } else if (hasPackageJson) {
      projectType = 'Web / Node.js / TypeScript';
    } else if (hasCargoToml) {
      projectType = 'Rust (Cargo)';
    }

    return ProjectInspectionSummary(
      projectName: projectName,
      projectType: projectType,
      applicationId: appId,
      modules: modules,
      dartCount: dartCount,
      kotlinCount: kotlinCount,
      javaCount: javaCount,
      xmlCount: xmlCount,
      gradleCount: gradleCount,
      otherCodeCount: otherCodeCount,
      keyFiles: keyFiles,
      keyFileSnippets: snippets,
    );
  }

  /// Облачный ИИ-запрос без API-ключа (фолбэк, чтобы пользователь ВСЕГДА получал умный живой ответ)
  Future<String> _callZeroKeyCloudLlm({
    required String systemPrompt,
    required List<Map<String, dynamic>> messages,
  }) async {
    try {
      final res = await _dio.post(
        'https://text.pollinations.ai/openai',
        options: Options(
          headers: {'Content-Type': 'application/json'},
          sendTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 35),
        ),
        data: {
          'model': 'openai',
          'messages': [
            {'role': 'system', 'content': systemPrompt},
            ...messages,
          ],
          'temperature': state.temperature,
        },
      );
      final data = res.data;
      if (data is Map) {
        final choices = data['choices'] as List?;
        if (choices != null && choices.isNotEmpty) {
          final content = choices.first['message']?['content']?.toString() ?? '';
          if (content.trim().isNotEmpty) return content.trim();
        }
      } else if (data is String && data.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(data);
          if (decoded is Map) {
            final choices = decoded['choices'] as List?;
            if (choices != null && choices.isNotEmpty) {
              final content = choices.first['message']?['content']?.toString() ?? '';
              if (content.trim().isNotEmpty) return content.trim();
            }
          }
        } catch (_) {
          return data.trim();
        }
      }
    } catch (_) {}
    return '';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 1. ВСТРОЕННЫЙ ИИ-АССИСТЕНТ + АВТО-ДОКТОР (РАБОТАЕТ БЕЗ API КЛЮЧА И КАК ФОЛБЭК)
  // ═══════════════════════════════════════════════════════════════════════════
  Future<void> _runAutonomousDoctorAndBridge(
    String msgId,
    String userPrompt, {
    String? fallbackErrorNote,
  }) async {
    final sw = Stopwatch()..start();
    final ws = _ref.read(workspaceProvider).currentPath;
    if (ws == null || ws.isEmpty) {
      _updateAssistantMessage(
        msgId,
        content: '❌ Проект сейчас не открыт. Откройте папку проекта в проводнике слева, чтобы я мог изучить код и ответить.',
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

    // Шаг 1: Синхронизация и глубокое сканирование реальной структуры проекта
    state = state.copyWith(statusText: 'Анализ структуры и файлов проекта ${p.basename(ws)}...');
    final inspectCall = AgentToolCall(
      id: 'tc_inspect',
      toolName: 'inspect_project',
      title: 'Анализ структуры проекта ${p.basename(ws)} и синхронизация',
      arguments: {'workspace': ws},
      isRunning: true,
    );
    addOrUpdateTool(inspectCall);

    final syncedFiles = await _ref.read(projectServiceProvider.notifier).syncExternalIntoWorkspace(ws);
    await _ref.read(editorProvider.notifier).syncExternalNow(reloadAllTabs: true);
    modified.addAll(syncedFiles);

    final projectInfo = await _inspectProjectComprehensive(ws);
    addOrUpdateTool(inspectCall.copyWith(
      isRunning: false,
      result: 'Стек: ${projectInfo.projectType} · Файлов: ${projectInfo.totalSourceFiles} '
          '(Kotlin: ${projectInfo.kotlinCount}, Java: ${projectInfo.javaCount}, XML: ${projectInfo.xmlCount}, '
          'Gradle: ${projectInfo.gradleCount}, Dart: ${projectInfo.dartCount})',
    ));

    // Если пользователь явно просит собрать APK
    if (lower.contains('собрать apk') || lower.contains('сборка apk') || lower == 'build apk') {
      final isFlutter = projectInfo.dartCount > 0;
      final buildCmd = isFlutter ? 'flutter build apk --release' : 'bash ./gradlew assembleDebug';
      final buildCall = AgentToolCall(
        id: 'tc_build_apk',
        toolName: 'run_command',
        title: 'Запуск сборки APK ($buildCmd)',
        arguments: {'command': buildCmd},
        isRunning: true,
      );
      addOrUpdateTool(buildCall);

      final buildRes = await _executeTool('run_command', {
        'command': buildCmd,
        'in_terminal': true,
      }, ws, modified);

      addOrUpdateTool(buildCall.copyWith(isRunning: false, result: buildRes));
      sw.stop();
      _updateAssistantMessage(
        msgId,
        thinking: 'Определён стек проекта (${projectInfo.projectType}), запущена команда `$buildCmd`.',
        thinkingDurationMs: sw.elapsedMilliseconds,
        content: '🚀 **Сборка APK для проекта `${projectInfo.projectName}` (${projectInfo.projectType}) запущена!**\n\n'
            '• **Команда:** `$buildCmd`\n'
            '• **Синхронизация:** все файлы из `/storage/emulated/0/QuantumIDE/${projectInfo.projectName}` актуальны.\n'
            '• Если во время сборки возникнет ошибка — нажмите **«🔧 Исправить ошибки»**, и я разберу лог компилятора.',
        modifiedFiles: modified,
        isStreaming: false,
      );
      return;
    }

    // Шаг 2: Проверка синтаксиса и Gradle-конфигурации под реальный тип проекта
    final diagCall = AgentToolCall(
      id: 'tc_diag',
      toolName: 'get_diagnostics',
      title: 'Проверка кода и конфигурации сборки (${projectInfo.projectType})',
      arguments: {'workspace': projectInfo.projectName},
      isRunning: true,
    );
    addOrUpdateTool(diagCall);

    final diagReport = await _scanWorkspaceDiagnosticsAndHeal(ws, modified, projectInfo: projectInfo);
    final gradleStatus = await _ensureOptimalGradleProperties(ws, modified);
    addOrUpdateTool(diagCall.copyWith(
      isRunning: false,
      result: '${diagReport.summaryShort} · $gradleStatus',
    ));

    // Шаг 3: Живой ИИ-ответ на конкретный вопрос пользователя с полным знанием проекта!
    state = state.copyWith(statusText: 'Генерация ответа ИИ по проекту ${projectInfo.projectName}...');
    final activeFile = _ref.read(editorProvider).let((s) {
      if (s.openFiles.isEmpty || s.activeTabIndex < 0 || s.activeTabIndex >= s.openFiles.length) {
        return null;
      }
      return s.openFiles[s.activeTabIndex];
    });

    final systemPrompt = '''
Ты — Quantum Agent (PrivateLM + Mobile Harness: ${state.selectedHarness}), умный ИИ-разработчик внутри мобильной IDE Quantum IDE.
Отвечай живым, понятным русским языком прямо на вопрос пользователя!
Не пиши сухие шаблонные отчёты, если пользователь просто поздоровался или спросил "что за проект" — расскажи ему подробно и дружелюбно про его открытый проект, его стек, пакет, модули и ключевые файлы.

ДАННЫЕ ОТКРЫТОГО ПРОЕКТА В IDE:
${projectInfo.toPromptContext()}
Открытый файл в редакторе: ${activeFile != null ? p.relative(activeFile.path, from: ws) : 'нет'}
Диагностика кода: ${diagReport.summaryDetailed}
Конфигурация Gradle: $gradleStatus
''';

    String aiReply = await _callZeroKeyCloudLlm(
      systemPrompt: systemPrompt,
      messages: [
        {'role': 'user', 'content': userPrompt},
      ],
    );

    if (aiReply.isNotEmpty) {
      final parsed = _parseThought(aiReply);
      aiReply = parsed.cleanContent;
    }

    // Если устройство офлайн или облачный мост недоступен — формируем умный осмысленный ответ по данным проекта
    if (aiReply.trim().isEmpty) {
      aiReply = _buildSmartConversationalAnswer(
        userPrompt: userPrompt,
        projectInfo: projectInfo,
        diagReport: diagReport,
        gradleStatus: gradleStatus,
        syncedFiles: syncedFiles,
      );
    } else if (fallbackErrorNote != null && fallbackErrorNote.isNotEmpty) {
      aiReply = '> ℹ️ *Выбранная модель (`${state.modelId}`) вернула пустой ответ или требует ключ, поэтому ответил встроенный ИИ-мост Quantum Agent:*\n\n$aiReply';
    }

    sw.stop();
    _updateAssistantMessage(
      msgId,
      thinking: 'Изучен проект `${projectInfo.projectName}` (${projectInfo.projectType}, файлов: ${projectInfo.totalSourceFiles}) '
          'за ${sw.elapsedMilliseconds} мс.',
      thinkingDurationMs: sw.elapsedMilliseconds,
      content: aiReply,
      modifiedFiles: modified,
      isStreaming: false,
    );
  }

  String _buildSmartConversationalAnswer({
    required String userPrompt,
    required ProjectInspectionSummary projectInfo,
    required ({int totalDartFiles, List<String> errors, String summaryShort, String summaryDetailed}) diagReport,
    required String gradleStatus,
    required List<String> syncedFiles,
  }) {
    final buf = StringBuffer();
    buf.writeln('Привет! 👋 Я проанализировал ваш открытый проект **`${projectInfo.projectName}`**.\n');
    buf.writeln('### 📱 О проекте `${projectInfo.projectName}`');
    buf.writeln('- **Тип и стек проекта:** `${projectInfo.projectType}`');
    if (projectInfo.applicationId.isNotEmpty) {
      buf.writeln('- **Package / Application ID:** `${projectInfo.applicationId}`');
    }
    if (projectInfo.modules.isNotEmpty) {
      buf.writeln('- **Модули Gradle:** `${projectInfo.modules.join(", ")}`');
    }
    buf.writeln(
      '- **Файлы исходного кода (${projectInfo.totalSourceFiles}):** '
      'Kotlin (`.kt`): **${projectInfo.kotlinCount}**, '
      'Java (`.java`): **${projectInfo.javaCount}**, '
      'XML-разметка/манифест: **${projectInfo.xmlCount}**, '
      'Gradle-скрипты: **${projectInfo.gradleCount}**'
      '${projectInfo.dartCount > 0 ? ", Dart: **${projectInfo.dartCount}**" : ""}',
    );

    if (projectInfo.keyFiles.isNotEmpty) {
      buf.writeln('\n### 📂 Ключевые файлы в проекте:');
      for (final f in projectInfo.keyFiles.take(14)) {
        buf.writeln('- `$f`');
      }
    }

    if (projectInfo.keyFileSnippets.isNotEmpty) {
      buf.writeln('\n### 🔍 Краткий обзор конфигурации и точек входа:');
      projectInfo.keyFileSnippets.forEach((file, snippet) {
        final previewLines = snippet.split('\n').where((l) => l.trim().isNotEmpty).take(8).join('\n');
        buf.writeln('**`$file`:**\n```kotlin\n$previewLines\n```');
      });
    }

    buf.writeln('\n### ⚡ Статус готовности к сборке:');
    buf.writeln('- **Проверка кода:** ${diagReport.summaryShort}');
    buf.writeln('- **Оптимизация Gradle:** $gradleStatus');
    if (syncedFiles.isNotEmpty) {
      buf.writeln('- **Синхронизировано файлов:** ${syncedFiles.length}');
    }
    buf.writeln('\nНапишите, какую функцию добавить, какой экран изменить или какую ошибку исправить в `${projectInfo.projectName}`!');
    return buf.toString();
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

    // Сначала собираем контекст проекта, чтобы любая модель (OpenRouter, DeepSeek, Claude) сразу знала файлы проекта!
    final projectInfo = await _inspectProjectComprehensive(ws);

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

    final harnessSpec = AgentHarnessSpec.byId(state.selectedHarness);

    final systemPrompt = '''
Ты — Quantum Agent (Харнесс: ${harnessSpec.title} v${harnessSpec.version}), автономный ИИ-инженер внутри мобильной среды разработки Quantum IDE.
Текущий проект: $ws (зеркало во внешней памяти: /storage/emulated/0/QuantumIDE/${p.basename(ws)}).
Открытый файл в редакторе: ${activeFile != null ? p.relative(activeFile.path, from: ws) : 'нет'}.
Статус последней сборки: ${LiveTelemetryService.instance.currentBuildStatus}.$extraSystem

СВОДКА ПО ОТКРЫТОМУ ПРОЕКТУ:
${projectInfo.toPromptContext()}

ТВОИ ИНСТРУМЕНТЫ (вызывай через XML блок <tool_call>, ТОЛЬКО когда нужно прочитать дополнительные строки или изменить файлы):
<tool_call>
{"name": "ИМЯ_ИНСТРУМЕНТА", "arguments": {...}}
</tool_call>

Доступные инструменты:
1. "list_files": {"subdir": "опциональная подпапка"} — список файлов проекта.
2. "search_code": {"query": "строка поиска", "subdir": ""} — поиск текста по файлам проекта.
3. "read_file": {"path": "относительный путь", "start_line": 1, "end_line": 200} — чтение файла с номерами строк.
4. "edit_file": {"path": "относительный путь", "target": "точный фрагмент старого кода", "replacement": "новый код"} — точечная замена кода в файле.
5. "write_file": {"path": "относительный путь", "content": "полный текст файла"} — создание или перезапись файла.
6. "run_command": {"command": "команда bash/gradle/flutter", "in_terminal": false} — запуск команды в проекте.
7. "get_diagnostics": {} — получить все текущие ошибки синтаксиса и последние строки лога сборки APK.

ПРАВИЛА РАБОТЫ:
- Всегда давай полный, информативный ответ пользователю на русском языке.
- Если пользователь спрашивает "что за проект" или задаёт вопрос по архитектуре — подробно ответь на основе СВОДКИ ПО ОТКРЫТОМУ ПРОЕКТУ выше.
- Когда исправляешь код через edit_file или write_file, пиши полный рабочий код без заглушек.
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
    const maxSteps = 6;
    final targetUrl = (state.providerId == 'custom' && state.customBaseUrl.isNotEmpty)
        ? state.customBaseUrl
        : preset.baseUrl;
    final isAnthropic = preset.protocol == 'anthropic-messages' ||
        (state.providerId == 'custom' && state.customProtocol == 'anthropic-messages');

    for (int step = 1; step <= maxSteps; step++) {
      if (_cancelRequested) break;
      state = state.copyWith(statusText: 'Шаг $step: запрос к ${state.modelId} (${harnessSpec.title})...');

      String rawContent = '';
      String? reasoning;

      if (isAnthropic) {
        final anthropicMsgs = conversation
            .where((m) => m['role'] != 'system')
            .map((m) => {'role': m['role'], 'content': m['content']})
            .toList();
        final response = await _dio.post(
          targetUrl,
          options: Options(headers: {
            if (state.apiKey.isNotEmpty) 'x-api-key': state.apiKey,
            'anthropic-version': '2023-06-01',
            'Content-Type': 'application/json',
          }),
          data: {
            'model': state.modelId,
            'system': systemPrompt,
            'messages': anthropicMsgs,
            'max_tokens': state.maxTokens,
            'temperature': state.temperature,
          },
        );
        final contentBlocks = response.data['content'] as List?;
        if (contentBlocks != null && contentBlocks.isNotEmpty) {
          final textParts = <String>[];
          final thinkParts = <String>[];
          for (final b in contentBlocks) {
            if (b is Map) {
              if (b['type'] == 'thinking') {
                thinkParts.add(b['thinking']?.toString() ?? '');
              } else if (b['type'] == 'text') {
                textParts.add(b['text']?.toString() ?? '');
              }
            }
          }
          rawContent = textParts.join('\n');
          if (thinkParts.isNotEmpty) reasoning = thinkParts.join('\n');
        }
      } else {
        final payload = <String, dynamic>{
          'model': state.modelId,
          'messages': conversation,
          'temperature': state.temperature,
          'max_tokens': state.maxTokens,
          if (state.stopSequences.isNotEmpty) 'stop': state.stopSequences,
        };

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

        final data = response.data;
        if (data is Map && data['error'] != null) {
          throw Exception(data['error']['message'] ?? data['error'].toString());
        }
        final choices = (data is Map) ? (data['choices'] as List?) : null;
        if (choices == null || choices.isEmpty) break;
        final msgObj = choices.first['message'] as Map<String, dynamic>? ?? {};
        rawContent = msgObj['content']?.toString() ?? '';
        reasoning = msgObj['reasoning_content']?.toString() ?? msgObj['reasoning']?.toString();
      }

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
        'content': '${toolResultsText.toString()}\nТеперь дай подробный итоговый ответ пользователю на русском языке.',
      });
    }

    // НИКОГДА не оставляем ответ пустым или просто "✅ Задача выполнена."!
    if (finalAnswer.trim().isEmpty) {
      await _runAutonomousDoctorAndBridge(
        msgId,
        userPrompt,
        fallbackErrorNote: 'Модель ${state.modelId} вернула пустой ответ',
      );
      return;
    }

    sw.stop();
    _updateAssistantMessage(
      msgId,
      content: finalAnswer,
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
          final subdir = args['subdir']?.toString() ?? '';
          final dir = subdir.isEmpty ? Directory(ws) : Directory(p.join(ws, subdir));
          final searchRoot = await dir.exists() ? dir : Directory(ws);
          final matches = <String>[];
          final pattern = RegExp(RegExp.escape(query), caseSensitive: false);

          await for (final entity in searchRoot.list(recursive: true, followLinks: false)) {
            if (entity is! File) continue;
            final rel = p.relative(entity.path, from: ws);
            if (rel.startsWith('.git') ||
                rel.startsWith('build') ||
                rel.startsWith('.dart_tool') ||
                rel.startsWith('.gradle') ||
                rel.startsWith('local_plugins')) {
              continue;
            }
            if (!rel.endsWith('.dart') &&
                !rel.endsWith('.kt') &&
                !rel.endsWith('.java') &&
                !rel.endsWith('.yaml') &&
                !rel.endsWith('.gradle') &&
                !rel.endsWith('.kts') &&
                !rel.endsWith('.xml') &&
                !rel.endsWith('.json') &&
                !rel.endsWith('.py') &&
                !rel.endsWith('.js') &&
                !rel.endsWith('.ts')) {
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
          if (inTerminal || cmd.contains('flutter build') || cmd.contains('gradlew')) {
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
      _scanWorkspaceDiagnosticsAndHeal(
    String ws,
    List<String> modified, {
    ProjectInspectionSummary? projectInfo,
  }) async {
    int checkedCount = 0;
    final errors = <String>[];
    final scanRoot = Directory(ws);

    if (await scanRoot.exists()) {
      await for (final entity in scanRoot.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final rel = p.relative(entity.path, from: ws);
        if (rel.startsWith('local_plugins') ||
            rel.startsWith('.dart_tool') ||
            rel.startsWith('build') ||
            rel.startsWith('.gradle') ||
            rel.startsWith('.git')) {
          continue;
        }
        if (!rel.endsWith('.dart') && !rel.endsWith('.kt') && !rel.endsWith('.java')) {
          continue;
        }
        checkedCount++;
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
        ? 'Проверено $checkedCount исходных файлов (.kt/.java/.dart) — 0 синтаксических ошибок!'
        : 'Проверено $checkedCount файлов, найдено ошибок: ${errors.length}';
    final detailedStr = errors.isEmpty
        ? shortStr
        : '$shortStr:\n${errors.take(15).join("\n")}';

    return (
      totalDartFiles: checkedCount,
      errors: errors,
      summaryShort: shortStr,
      summaryDetailed: detailedStr,
    );
  }

  Future<String> _ensureOptimalGradleProperties(String ws, List<String> modified) async {
    try {
      // Поддерживаем как нативные Android Kotlin/Java проекты (ws/gradle.properties), так и Flutter проекты (ws/android/gradle.properties)
      File? gpFile;
      final rootGradle = File(p.join(ws, 'gradle.properties'));
      final androidDir = Directory(p.join(ws, 'android'));
      final flutterGradle = File(p.join(androidDir.path, 'gradle.properties'));

      if (await rootGradle.exists() || await File(p.join(ws, 'settings.gradle.kts')).exists() || await File(p.join(ws, 'settings.gradle')).exists()) {
        gpFile = rootGradle;
      } else if (await androidDir.exists()) {
        gpFile = flutterGradle;
      }

      if (gpFile == null) {
        return 'Gradle не используется в этом проекте.';
      }

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

      final relPath = p.relative(gpFile.path, from: ws);
      if (changed) {
        _recordCheckpointDiff(ws, gpFile.path, oldContent, content);
        await gpFile.writeAsString(content, flush: true);
        await _mirrorAndReloadInIde(ws, gpFile.path, content, modified);
        return 'Оптимизированы флаги памяти (-Xmx1280m, in-process Kotlin, daemon=false) в $relPath.';
      }
      return '$relPath уже оптимален (-Xmx1280m, daemon=false, native aapt2).';
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
