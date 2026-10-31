import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:file_picker/file_picker.dart';

import 'package:quantum_ide/core/models/ai_provider_config.dart';
import 'package:quantum_ide/core/services/ai_service.dart';
import 'package:quantum_ide/core/services/local_ai_service.dart';
import 'package:quantum_ide/core/services/native_llama_service.dart';

// ─── Design Tokens (PrivateLM Visual System) ─────────────────────────────────

class _PrivateLmTokens {
  static const bg = Color(0xFF0C0D11);
  static const surface = Color(0xFF14151B);
  static const card = Color(0xFF181A22);
  static const hairline = Color(0x1AFFFFFF);
  static const accent = Color(0xFF00D2FF);
  static const accentPurple = Color(0xFF9D65FF);
  static const muted = Color(0xFF8E90A6);
  static const faint = Color(0xFF555770);
  static const green = Color(0xFF30D158);
  static const orange = Color(0xFFFF9F0A);
  static const red = Color(0xFFFF453A);
}

// ─── Modal Entrypoint ────────────────────────────────────────────────────────

Future<String?> showModelPickerModal(
  BuildContext context, {
  required String providerId,
  required String currentModel,
  String? apiKey,
  String? baseUrl,
  int initialMainTab = 0,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => ModelSelectionSheet(
      providerId: providerId,
      currentModel: currentModel,
      apiKey: apiKey,
      baseUrl: baseUrl,
      initialMainTab: initialMainTab,
    ),
  );
}

class ModelSelectionSheet extends ConsumerStatefulWidget {
  final String providerId;
  final String currentModel;
  final String? apiKey;
  final String? baseUrl;
  final int initialMainTab;

  const ModelSelectionSheet({
    super.key,
    required this.providerId,
    required this.currentModel,
    this.apiKey,
    this.baseUrl,
    this.initialMainTab = 0,
  });

  @override
  ConsumerState<ModelSelectionSheet> createState() => _ModelSelectionSheetState();
}

enum _MainTab { localAi, privateLmServer, cloudProviders, logs }
enum _LocalSubTab { myModels, catalog, settings }

class _ModelSelectionSheetState extends ConsumerState<ModelSelectionSheet> {
  late _MainTab _mainTab;
  _LocalSubTab _localSubTab = _LocalSubTab.myModels;
  String _catalogCategory = 'Все';

  // Cloud provider state
  String _selectedCloudProviderId = 'openrouter';
  final _cloudApiKeyController = TextEditingController();
  final _cloudBaseUrlController = TextEditingController();
  final _cloudSearchController = TextEditingController();
  List<DiscoveredModel> _cloudModels = [];
  bool _isDiscoveringCloud = false;
  String? _cloudStatusMessage;
  bool _cloudStatusOk = true;

  // PrivateLM (Second Phone) server state
  final _serverUrlController = TextEditingController();
  final _serverApiKeyController = TextEditingController();
  List<DiscoveredModel> _serverModels = [];
  bool _isTestingServer = false;
  ServerHealthResult? _serverHealth;

  // Local settings values
  final _systemPromptController = TextEditingController();
  double _temperature = 0.7;
  int _maxTokens = 4096;
  double _topP = 0.95;
  int _cpuThreads = 4;
  int _gpuLayers = 16;
  bool _useFlashAttn = true;

  @override
  void initState() {
    super.initState();
    final aiSvc = ref.read(aiServiceProvider);

    // Initial Tab resolution
    if (widget.initialMainTab == 2) {
      _mainTab = _MainTab.logs;
    } else if (widget.providerId == 'local_edge') {
      _mainTab = _MainTab.localAi;
      if (widget.initialMainTab == 1) _localSubTab = _LocalSubTab.settings;
    } else if (widget.providerId == 'privatelm') {
      _mainTab = _MainTab.privateLmServer;
    } else {
      _mainTab = _MainTab.cloudProviders;
      _selectedCloudProviderId = widget.providerId;
    }

    // Load saved settings
    _temperature = aiSvc.temperature;
    _maxTokens = aiSvc.maxTokens;
    _topP = aiSvc.topP;
    _systemPromptController.text = aiSvc.systemPrompt;

    final localState = ref.read(localAiServiceProvider);
    _cpuThreads = localState.threads;
    _gpuLayers = localState.gpuLayers > 0 ? localState.gpuLayers : 16;
    _useFlashAttn = localState.useFlashAttn;

    // Second Phone (PrivateLM) setup
    var savedServerUrl = aiSvc.getBaseUrl('privatelm');
    if (savedServerUrl.isEmpty || savedServerUrl == 'http://localhost:8080/v1') {
      savedServerUrl = 'http://10.109.133.237:8080/v1';
    }
    _serverUrlController.text = savedServerUrl;
    _serverApiKeyController.text = aiSvc.getApiKey('privatelm');
    _serverModels = aiSvc.getCachedDiscoveredModels('privatelm');
    _serverHealth = aiSvc.lastServerHealth;

    // Cloud setup
    _cloudApiKeyController.text = aiSvc.getApiKey(_selectedCloudProviderId);
    _cloudBaseUrlController.text = aiSvc.getBaseUrl(_selectedCloudProviderId);
    _cloudModels = aiSvc.getCachedDiscoveredModels(_selectedCloudProviderId);
    if (_cloudModels.isEmpty) {
      _cloudModels = AiProviders.getRecommendedDiscoveredModels(_selectedCloudProviderId);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_mainTab == _MainTab.privateLmServer) {
        _testServerConnection();
      } else if (_mainTab == _MainTab.cloudProviders) {
        _discoverCloudModels();
      }
    });
  }

  @override
  void dispose() {
    _cloudSearchController.dispose();
    _cloudApiKeyController.dispose();
    _cloudBaseUrlController.dispose();
    _serverUrlController.dispose();
    _serverApiKeyController.dispose();
    _systemPromptController.dispose();
    super.dispose();
  }

  // ─── Core Switcher / State Synchronizer ────────────────────────────────────

  void _selectAndApplyProviderAndModel(String providerId, String modelId) {
    final aiSvc = ref.read(aiServiceProvider);
    aiSvc.setProvider(providerId);
    aiSvc.setModel(modelId);
    ref.read(activeAiProviderIdProvider.notifier).state = providerId;
    ref.read(activeAiModelProvider.notifier).state = modelId;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(LucideIcons.check_circle_2, color: _PrivateLmTokens.green, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Активировано в чате: ${AiProviders.byId(providerId).displayName} · ${_formatModelTitle(modelId)}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF181A22),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: _PrivateLmTokens.green, width: 0.8),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
      Navigator.of(context).pop(modelId);
    }
  }

  // ─── PrivateLM (Second Phone) Connection Test & Discovery ──────────────────

  Future<void> _testServerConnection() async {
    setState(() => _isTestingServer = true);
    final aiSvc = ref.read(aiServiceProvider);
    final url = _serverUrlController.text.trim();
    final key = _serverApiKeyController.text.trim();

    await aiSvc.setBaseUrl('privatelm', url);
    if (key.isNotEmpty) {
      await aiSvc.setApiKey('privatelm', key);
    }

    try {
      final health = await aiSvc.testPrivateLmConnection(url, apiKey: key);
      if (!mounted) return;
      setState(() {
        _isTestingServer = false;
        _serverHealth = health;
        if (health.models.isNotEmpty) {
          _serverModels = health.models;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isTestingServer = false;
        _serverHealth = ServerHealthResult(
          isOk: false,
          latencyMs: 0,
          errorMessage: e.toString(),
        );
      });
    }
  }

  // ─── Cloud Provider Discovery ──────────────────────────────────────────────

  Future<void> _discoverCloudModels() async {
    setState(() {
      _isDiscoveringCloud = true;
      _cloudStatusMessage = null;
    });

    try {
      final aiSvc = ref.read(aiServiceProvider);
      final models = await aiSvc.discoverModels(
        _selectedCloudProviderId,
        customApiKey: _cloudApiKeyController.text.trim(),
        customBaseUrl: _cloudBaseUrlController.text.trim(),
      );

      if (!mounted) return;
      setState(() {
        _cloudModels = models;
        _isDiscoveringCloud = false;
        _cloudStatusMessage = models.isEmpty
            ? 'Список моделей пуст — проверьте API ключ'
            : 'Доступно моделей: ${models.length}';
        _cloudStatusOk = models.isNotEmpty;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isDiscoveringCloud = false;
        _cloudStatusMessage = 'Ошибка подключения: $e';
        _cloudStatusOk = false;
      });
    }
  }

  void _onCloudProviderChanged(String pid) {
    final aiSvc = ref.read(aiServiceProvider);
    setState(() {
      _selectedCloudProviderId = pid;
      _cloudApiKeyController.text = aiSvc.getApiKey(pid);
      _cloudBaseUrlController.text = aiSvc.getBaseUrl(pid);
      _cloudModels = aiSvc.getCachedDiscoveredModels(pid);
      if (_cloudModels.isEmpty) {
        _cloudModels = AiProviders.getRecommendedDiscoveredModels(pid);
      }
    });
    _discoverCloudModels();
  }

  // ─── Local Engine Launcher ────────────────────────────────────────────────

  Future<void> _startModelSafely(String filename, {String? modelPath}) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final path = modelPath ?? (await ref.read(localAiServiceProvider.notifier).findModelFile(filename))?.path;
      if (path != null && await File(path).exists()) {
        final gpu = ref.read(nativeLlamaServiceProvider).gpuInfo;
        final gpuLayers = (gpu != null && gpu.vulkanSupported) ? gpu.recommendedGpuLayers : 16;
        await ref.read(nativeLlamaServiceProvider.notifier).loadModel(
          modelPath: path,
          gpuLayers: gpuLayers,
        );
        await ref.read(aiServiceProvider).setLocalEngine(LocalAiEngine.nativeLlama);
        _selectAndApplyProviderAndModel('local_edge', filename);
        return;
      }
    } catch (e) {
      debugPrint('[NativeLlama] Load error, fallback: $e');
    }

    await ref.read(localAiServiceProvider.notifier).selectAndStartModel(filename);
    _selectAndApplyProviderAndModel('local_edge', filename);
  }

  Future<void> _importLocalModelFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['gguf', 'litertlm', 'bin'],
      );
      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        final name = path.split('/').last;
        await _startModelSafely(name, modelPath: path);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка импорта: $e')),
      );
    }
  }

  static String _formatModelTitle(String raw) {
    var name = raw.replaceAll(r'\', '/');
    if (name.contains('/')) name = name.split('/').last;
    name = name.replaceAll('.gguf', '').replaceAll('.litertlm', '');
    name = name.replaceAll('-instruct', '').replaceAll('-chat', '');
    return name;
  }

  // ─── Main Scaffold Build ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.92,
      decoration: const BoxDecoration(
        color: _PrivateLmTokens.bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // Drag handle
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Top Header Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: _PrivateLmTokens.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(LucideIcons.sparkles, size: 16, color: _PrivateLmTokens.accent),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'AI Hub & Выбор моделей',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'Локальная ИИ · Второй телефон · Облако',
                        style: GoogleFonts.inter(fontSize: 11, color: _PrivateLmTokens.muted),
                      ),
                    ],
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(LucideIcons.x, size: 18, color: Colors.white60),
                    onPressed: () => Navigator.of(context).pop(),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.05),
                      padding: const EdgeInsets.all(6),
                      minimumSize: const Size(32, 32),
                    ),
                  ),
                ],
              ),
            ),

            // Top Segmented Modules Switcher (4 Distinct Modules)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: _buildMainModuleTabs(),
            ),

            const SizedBox(height: 6),

            // Module Body
            Expanded(
              child: switch (_mainTab) {
                _MainTab.localAi => _buildLocalAiTab(),
                _MainTab.privateLmServer => _buildPrivateLmServerTab(),
                _MainTab.cloudProviders => _buildCloudProvidersTab(),
                _MainTab.logs => _buildLogsTab(),
              },
            ),
          ],
        ),
      ),
    );
  }

  // ─── Module Tabs Switcher ─────────────────────────────────────────────────

  Widget _buildMainModuleTabs() {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: _PrivateLmTokens.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _PrivateLmTokens.hairline),
      ),
      child: Row(
        children: [
          _moduleTabButton(_MainTab.localAi, 'Этот телефон', LucideIcons.cpu, 'Локально'),
          _moduleTabButton(_MainTab.privateLmServer, 'Второй телефон', LucideIcons.smartphone, 'PrivateLM'),
          _moduleTabButton(_MainTab.cloudProviders, 'Облачные API', LucideIcons.cloud, 'OpenRouter/etc'),
          _moduleTabButton(_MainTab.logs, 'Логи', LucideIcons.terminal, ''),
        ],
      ),
    );
  }

  Widget _moduleTabButton(_MainTab tab, String label, IconData icon, String badge) {
    final isSel = _mainTab == tab;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _mainTab = tab);
          if (tab == _MainTab.privateLmServer && _serverHealth == null) {
            _testServerConnection();
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: isSel ? Colors.white.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 12, color: isSel ? _PrivateLmTokens.accent : _PrivateLmTokens.muted),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      label,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                        color: isSel ? Colors.white : _PrivateLmTokens.muted,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MODULE 1: ЛОКАЛЬНАЯ ИИ (НА ЭТОМ ТЕЛЕФОНЕ)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildLocalAiTab() {
    final nativeLlama = ref.watch(nativeLlamaServiceProvider);
    final gpu = nativeLlama.gpuInfo;

    return Column(
      children: [
        // Hardware Acceleration Banner
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF10131B),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white10),
          ),
          child: Row(
            children: [
              Icon(LucideIcons.zap, size: 14, color: gpu?.vulkanSupported == true ? _PrivateLmTokens.green : _PrivateLmTokens.orange),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  gpu != null
                      ? '${gpu.gpuName} · Vulkan GPU: ${gpu.vulkanSupported ? "Активен" : "Откл"} · Слоев: ${gpu.recommendedGpuLayers}'
                      : 'Встроенный движок Native Llama (ARM64)',
                  style: GoogleFonts.jetBrainsMono(fontSize: 10.5, color: Colors.white70),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),

        // Sub-tabs: [ Мои GGUF | Каталог | Настройки GPU/CPU ]
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Row(
              children: [
                _localSubTabButton(_LocalSubTab.myModels, 'Мои GGUF', LucideIcons.hard_drive),
                _localSubTabButton(_LocalSubTab.catalog, 'Скачать из каталога', LucideIcons.download),
                _localSubTabButton(_LocalSubTab.settings, 'Настройки GPU', LucideIcons.sliders_horizontal),
              ],
            ),
          ),
        ),

        const SizedBox(height: 4),

        Expanded(
          child: switch (_localSubTab) {
            _LocalSubTab.myModels => _buildLocalMyModelsView(),
            _LocalSubTab.catalog => _buildLocalCatalogView(),
            _LocalSubTab.settings => _buildLocalSettingsView(),
          },
        ),
      ],
    );
  }

  Widget _localSubTabButton(_LocalSubTab tab, String label, IconData icon) {
    final isSel = _localSubTab == tab;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _localSubTab = tab),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isSel ? _PrivateLmTokens.card : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
            border: isSel ? Border.all(color: _PrivateLmTokens.hairline) : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 11, color: isSel ? _PrivateLmTokens.accent : _PrivateLmTokens.faint),
              const SizedBox(width: 4),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: isSel ? FontWeight.w600 : FontWeight.w400,
                  color: isSel ? Colors.white : _PrivateLmTokens.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLocalMyModelsView() {
    final localState = ref.watch(localAiServiceProvider);
    final nativeLlama = ref.watch(nativeLlamaServiceProvider);
    final downloadedIds = localState.downloadedModels.entries.where((e) => e.value).map((e) => e.key).toList();

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      children: [
        // Import Button
        OutlinedButton.icon(
          onPressed: _importLocalModelFile,
          icon: const Icon(LucideIcons.file_up, size: 14, color: _PrivateLmTokens.accent),
          label: const Text('Импортировать .gguf с диска устройства', style: TextStyle(fontSize: 12)),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: _PrivateLmTokens.hairline),
            padding: const EdgeInsets.symmetric(vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        const SizedBox(height: 10),

        if (downloadedIds.isEmpty)
          Container(
            padding: const EdgeInsets.all(30),
            alignment: Alignment.center,
            child: Column(
              children: [
                const Icon(LucideIcons.hard_drive, size: 36, color: _PrivateLmTokens.faint),
                const SizedBox(height: 10),
                const Text('Нет скачанных локальных моделей', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                const Text('Перейдите в «Скачать из каталога» или импортируйте GGUF файл.', style: TextStyle(color: _PrivateLmTokens.muted, fontSize: 11), textAlign: TextAlign.center),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () => setState(() => _localSubTab = _LocalSubTab.catalog),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _PrivateLmTokens.accent,
                    foregroundColor: Colors.black,
                  ),
                  child: const Text('Открыть каталог', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          )
        else
          ...downloadedIds.map((id) {
            final model = availableLocalModels.firstWhere(
              (m) => m.id == id,
              orElse: () => LocalModelInfo(
                id: id,
                name: id,
                description: 'Локальная модель GGUF',
                filename: id,
                sizeGb: 1.0,
                ramRequiredGb: 2.0,
                url: '',
                engine: LocalAiEngine.nativeLlama,
              ),
            );

            final isRunning = (nativeLlama.isModelLoaded && (nativeLlama.loadedModelPath?.contains(model.filename) ?? false)) ||
                (localState.selectedModelFilename == model.filename && localState.isRunning);

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _PrivateLmTokens.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isRunning ? _PrivateLmTokens.green.withValues(alpha: 0.5) : _PrivateLmTokens.hairline),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.cpu, size: 16, color: isRunning ? _PrivateLmTokens.green : Colors.white60),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(model.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12.5)),
                        Text('${model.sizeGb.toStringAsFixed(1)} GB · GGUF', style: const TextStyle(color: _PrivateLmTokens.muted, fontSize: 10.5)),
                      ],
                    ),
                  ),
                  if (isRunning)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _PrivateLmTokens.green.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('🟢 В памяти', style: TextStyle(color: _PrivateLmTokens.green, fontSize: 10.5, fontWeight: FontWeight.bold)),
                    )
                  else
                    ElevatedButton(
                      onPressed: () => _startModelSafely(model.filename),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _PrivateLmTokens.accent,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        minimumSize: Size.zero,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      child: const Text('⚡ Запустить', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  IconButton(
                    icon: const Icon(LucideIcons.trash_2, size: 14, color: Colors.white30),
                    onPressed: () => ref.read(localAiServiceProvider.notifier).deleteModel(model.id),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _buildLocalCatalogView() {
    final localState = ref.watch(localAiServiceProvider);
    final categories = ['Все', 'Кодинг', 'Рассуждения', 'Компактные'];

    final filtered = availableLocalModels.where((m) {
      if (_catalogCategory == 'Кодинг') return m.name.toLowerCase().contains('coder');
      if (_catalogCategory == 'Рассуждения') return m.name.toLowerCase().contains('r1');
      if (_catalogCategory == 'Компактные') return m.sizeGb < 1.5;
      return true;
    }).toList();

    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: categories.map((cat) {
              final isSel = _catalogCategory == cat;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(cat, style: TextStyle(fontSize: 10.5, color: isSel ? Colors.black : Colors.white70)),
                  selected: isSel,
                  selectedColor: _PrivateLmTokens.accent,
                  backgroundColor: _PrivateLmTokens.surface,
                  onSelected: (_) => setState(() => _catalogCategory = cat),
                ),
              );
            }).toList(),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            itemCount: filtered.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, idx) {
              final model = filtered[idx];
              final isDownloaded = localState.downloadedModels[model.id] == true;
              final isDownloading = localState.downloadingModelId == model.id;

              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _PrivateLmTokens.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _PrivateLmTokens.hairline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(model.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
                        Text('${model.sizeGb.toStringAsFixed(1)} GB', style: const TextStyle(color: _PrivateLmTokens.accent, fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(model.description, style: const TextStyle(color: _PrivateLmTokens.muted, fontSize: 11)),
                    const SizedBox(height: 8),
                    if (isDownloading) ...[
                      LinearProgressIndicator(value: localState.downloadProgress, color: _PrivateLmTokens.accent, backgroundColor: Colors.white10),
                      const SizedBox(height: 6),
                      Text('Загрузка: ${(localState.downloadProgress * 100).toStringAsFixed(1)}%', style: const TextStyle(color: _PrivateLmTokens.muted, fontSize: 10.5)),
                    ] else if (isDownloaded)
                      ElevatedButton(
                        onPressed: () => _startModelSafely(model.filename),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _PrivateLmTokens.green,
                          foregroundColor: Colors.black,
                          minimumSize: const Size(double.infinity, 32),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                        child: const Text('⚡ Запустить на GPU', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      )
                    else
                      ElevatedButton.icon(
                        onPressed: () => ref.read(localAiServiceProvider.notifier).downloadModel(model),
                        icon: const Icon(LucideIcons.download, size: 12),
                        label: const Text('Скачать модель', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.1),
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 32),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLocalSettingsView() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      children: [
        _sliderSetting(
          label: 'Слои GPU (Vulkan Offload)',
          valueStr: '$_gpuLayers слоев',
          value: _gpuLayers.toDouble(),
          min: 0,
          max: 33,
          divisions: 33,
          hint: 'Ускорение на Adreno GPU через Vulkan (рекомендуется: 16-24)',
          onChanged: (v) {
            setState(() => _gpuLayers = v.toInt());
            ref.read(localAiServiceProvider.notifier).setGpuLayers(v.toInt());
          },
        ),
        const SizedBox(height: 12),
        _sliderSetting(
          label: 'Потоки CPU',
          valueStr: '$_cpuThreads потоков',
          value: _cpuThreads.toDouble(),
          min: 1,
          max: 8,
          divisions: 7,
          hint: 'Количество ядер процессора для инференса',
          onChanged: (v) {
            setState(() => _cpuThreads = v.toInt());
            ref.read(localAiServiceProvider.notifier).setThreads(v.toInt());
          },
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Flash Attention (FlashAttn)', style: TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold)),
          subtitle: const Text('Ускоряет обработку длинного контекста и экономит RAM', style: TextStyle(fontSize: 10.5, color: _PrivateLmTokens.muted)),
          value: _useFlashAttn,
          activeColor: _PrivateLmTokens.accent,
          onChanged: (v) {
            setState(() => _useFlashAttn = v);
            ref.read(localAiServiceProvider.notifier).setUseFlashAttn(v);
          },
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MODULE 2: СЕРВЕР PRIVATELM (ВТОРОЙ ТЕЛЕФОН ПО WI-FI)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildPrivateLmServerTab() {
    final aiSvc = ref.watch(aiServiceProvider);
    final health = _serverHealth;
    final isOnline = health?.isOk == true;
    final detectedModel = health?.activeModel ?? aiSvc.lastDetectedServerModel;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      children: [
        // Server Description Card
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _PrivateLmTokens.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _PrivateLmTokens.hairline),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _PrivateLmTokens.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(LucideIcons.smartphone, size: 20, color: _PrivateLmTokens.accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Второй телефон (PrivateLM Сервер)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 2),
                    Text(
                      'Модель запускается на втором телефоне по Wi-Fi. На этом устройстве ресурсы не расходуются.',
                      style: GoogleFonts.inter(fontSize: 10.5, color: _PrivateLmTokens.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Connection Settings Box
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _PrivateLmTokens.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: isOnline ? _PrivateLmTokens.green.withValues(alpha: 0.4) : _PrivateLmTokens.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Wi-Fi URL сервера:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white70)),
              const SizedBox(height: 6),
              TextField(
                controller: _serverUrlController,
                style: GoogleFonts.jetBrainsMono(fontSize: 12, color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'http://10.109.133.237:8080/v1',
                  hintStyle: const TextStyle(fontSize: 11, color: Colors.white24),
                  filled: true,
                  fillColor: Colors.black26,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  isDense: true,
                  suffixIcon: IconButton(
                    icon: const Icon(LucideIcons.paste, size: 14, color: Colors.white60),
                    tooltip: 'Вставить из буфера',
                    onPressed: () async {
                      final data = await Clipboard.getData('text/plain');
                      if (data?.text != null) {
                        _serverUrlController.text = data!.text!.trim();
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Presets chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _presetUrlChip('10.109.133.237:8080', 'http://10.109.133.237:8080/v1'),
                    _presetUrlChip('192.168.1.100:8080', 'http://192.168.1.100:8080/v1'),
                    _presetUrlChip('127.0.0.1:8080', 'http://127.0.0.1:8080/v1'),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              const Text('API Ключ (необязательно):', style: TextStyle(fontSize: 11, color: _PrivateLmTokens.muted)),
              const SizedBox(height: 4),
              TextField(
                controller: _serverApiKeyController,
                obscureText: true,
                style: GoogleFonts.jetBrainsMono(fontSize: 12, color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'aichat_...',
                  hintStyle: const TextStyle(fontSize: 11, color: Colors.white24),
                  filled: true,
                  fillColor: Colors.black26,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  isDense: true,
                ),
              ),

              const SizedBox(height: 12),

              // Connect Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isTestingServer ? null : _testServerConnection,
                  icon: _isTestingServer
                      ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                      : const Icon(LucideIcons.wifi, size: 14),
                  label: Text(
                    _isTestingServer ? 'Проверка соединения...' : 'Проверить связь и найти активную модель',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _PrivateLmTokens.accent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // ── HERO КАРТА: ТЕКУЩАЯ МОДЕЛЬ НА СЕРВЕРЕ ──
        if (isOnline) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _PrivateLmTokens.green.withValues(alpha: 0.15),
                  _PrivateLmTokens.accent.withValues(alpha: 0.08),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _PrivateLmTokens.green.withValues(alpha: 0.6), width: 1.2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: _PrivateLmTokens.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'СЕРВЕР ПОДКЛЮЧЕН · ${health.latencyMs} ms',
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: _PrivateLmTokens.green),
                    ),
                    const Spacer(),
                    const Icon(LucideIcons.sparkles, size: 14, color: _PrivateLmTokens.accent),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'АКТИВНАЯ МОДЕЛЬ НА ВТОРОМ ТЕЛЕФОНЕ:',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white60, letterSpacing: 0.5),
                ),
                const SizedBox(height: 4),
                Text(
                  detectedModel != null ? _formatModelTitle(detectedModel) : 'Текущая модель PrivateLM',
                  style: GoogleFonts.jetBrainsMono(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Модель готова принимать запросы в чате через Wi-Fi без задержек.',
                  style: TextStyle(fontSize: 11, color: _PrivateLmTokens.muted),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      final mId = detectedModel ?? 'default';
                      _selectAndApplyProviderAndModel('privatelm', mId);
                    },
                    icon: const Icon(LucideIcons.check_circle, size: 14),
                    label: const Text('⚡ Выбрать эту модель для чата', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _PrivateLmTokens.green,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ] else if (health != null && !health.isOk) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _PrivateLmTokens.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _PrivateLmTokens.orange.withValues(alpha: 0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(LucideIcons.alert_triangle, size: 16, color: _PrivateLmTokens.orange),
                    const SizedBox(width: 8),
                    const Text('Сервер не отвечает', style: TextStyle(color: _PrivateLmTokens.orange, fontWeight: FontWeight.bold, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  health.errorMessage ?? 'Не удалось подключиться к порту 8080',
                  style: GoogleFonts.jetBrainsMono(fontSize: 10.5, color: Colors.white70),
                ),
                const SizedBox(height: 8),
                const Text(
                  '• Убедитесь, что сервер PrivateLM запущен на втором телефоне\n• Оба телефона должны быть в одной Wi-Fi сети\n• Проверьте IP адрес в строке подключения',
                  style: TextStyle(fontSize: 10.5, color: _PrivateLmTokens.muted, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],

        // Список всех моделей сервера
        Text(
          'Модели на сервере (${_serverModels.length}):',
          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: _PrivateLmTokens.muted),
        ),
        const SizedBox(height: 8),

        if (_serverModels.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            alignment: Alignment.center,
            child: const Text('Нажмите «Проверить связь», чтобы загрузить список моделей с сервера.', style: TextStyle(color: _PrivateLmTokens.faint, fontSize: 11), textAlign: TextAlign.center),
          )
        else
          ..._serverModels.map((m) {
            final isAct = m.isServerActive || m.id == detectedModel;
            final isCurrent = aiSvc.selectedModel == m.id && aiSvc.selectedProviderId == 'privatelm';

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: _PrivateLmTokens.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isAct ? _PrivateLmTokens.green.withValues(alpha: 0.6) : (isCurrent ? _PrivateLmTokens.accent : _PrivateLmTokens.hairline),
                  width: isAct ? 1.2 : 0.8,
                ),
              ),
              child: ListTile(
                dense: true,
                leading: Icon(
                  isAct ? LucideIcons.sparkles : LucideIcons.cpu,
                  size: 16,
                  color: isAct ? _PrivateLmTokens.green : Colors.white60,
                ),
                title: Text(
                  m.displayName,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11.5,
                    fontWeight: isAct || isCurrent ? FontWeight.bold : FontWeight.normal,
                    color: Colors.white,
                  ),
                ),
                trailing: isAct
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: _PrivateLmTokens.green.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('🟢 Запущена', style: TextStyle(color: _PrivateLmTokens.green, fontSize: 10, fontWeight: FontWeight.bold)),
                      )
                    : (isCurrent ? const Icon(LucideIcons.check, size: 14, color: _PrivateLmTokens.accent) : null),
                onTap: () => _selectAndApplyProviderAndModel('privatelm', m.id),
              ),
            );
          }),
      ],
    );
  }

  Widget _presetUrlChip(String label, String url) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ActionChip(
        label: Text(label, style: const TextStyle(fontSize: 10, color: Colors.white70)),
        backgroundColor: Colors.white.withValues(alpha: 0.06),
        padding: EdgeInsets.zero,
        onPressed: () {
          _serverUrlController.text = url;
          _testServerConnection();
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MODULE 3: ОБЛАЧНЫЕ ПРОВАЙДЕРЫ (OPENROUTER, DEEPSEEK, GOOGLE, CLAUDE, ETC.)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildCloudProvidersTab() {
    final aiSvc = ref.watch(aiServiceProvider);
    final providers = [
      AiProviders.openrouter,
      AiProviders.deepseek,
      AiProviders.google,
      AiProviders.anthropic,
      AiProviders.openai,
      AiProviders.groq,
      AiProviders.mistral,
      AiProviders.together,
      AiProviders.custom,
    ];

    final query = _cloudSearchController.text.trim().toLowerCase();
    final filtered = _cloudModels.where((m) {
      if (query.isEmpty) return true;
      return m.id.toLowerCase().contains(query) || m.displayName.toLowerCase().contains(query);
    }).toList();

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      children: [
        // Horizontal Provider Switcher
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: providers.map((p) {
              final isSel = p.id == _selectedCloudProviderId;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(
                    '${p.logoEmoji} ${p.displayName}',
                    style: TextStyle(fontSize: 11, fontWeight: isSel ? FontWeight.bold : FontWeight.normal, color: isSel ? Colors.black : Colors.white70),
                  ),
                  selected: isSel,
                  selectedColor: _PrivateLmTokens.accent,
                  backgroundColor: _PrivateLmTokens.surface,
                  onSelected: (_) => _onCloudProviderChanged(p.id),
                ),
              );
            }).toList(),
          ),
        ),

        const SizedBox(height: 10),

        // Config Card for Selected Provider
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _PrivateLmTokens.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _PrivateLmTokens.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('API Ключ для ${_selectedCloudProviderId.toUpperCase()}:', style: const TextStyle(fontSize: 11, color: _PrivateLmTokens.muted)),
              const SizedBox(height: 4),
              TextField(
                controller: _cloudApiKeyController,
                obscureText: true,
                style: GoogleFonts.jetBrainsMono(fontSize: 12, color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'sk-... или ключ доступа',
                  hintStyle: const TextStyle(fontSize: 11, color: Colors.white24),
                  filled: true,
                  fillColor: Colors.black26,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: () async {
                      final key = _cloudApiKeyController.text.trim();
                      await aiSvc.setApiKey(_selectedCloudProviderId, key);
                      _discoverCloudModels();
                    },
                    icon: _isDiscoveringCloud
                        ? const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.black))
                        : const Icon(LucideIcons.check, size: 12),
                    label: const Text('Сохранить и обновить модели', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _PrivateLmTokens.accent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      minimumSize: Size.zero,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  if (_cloudStatusMessage != null) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _cloudStatusMessage!,
                        style: TextStyle(fontSize: 10.5, color: _cloudStatusOk ? _PrivateLmTokens.green : _PrivateLmTokens.orange),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Search Bar
        TextField(
          controller: _cloudSearchController,
          onChanged: (_) => setState(() {}),
          style: GoogleFonts.inter(fontSize: 12, color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Поиск моделей...',
            hintStyle: const TextStyle(fontSize: 11, color: Colors.white30),
            prefixIcon: const Icon(LucideIcons.search, size: 14, color: Colors.white38),
            filled: true,
            fillColor: _PrivateLmTokens.surface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _PrivateLmTokens.hairline)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            isDense: true,
          ),
        ),

        const SizedBox(height: 10),

        // Models List
        ...filtered.map((m) {
          final isCurrent = aiSvc.selectedModel == m.id && aiSvc.selectedProviderId == _selectedCloudProviderId;

          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              color: _PrivateLmTokens.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: isCurrent ? _PrivateLmTokens.accent : _PrivateLmTokens.hairline),
            ),
            child: ListTile(
              dense: true,
              leading: Icon(
                m.isFree ? LucideIcons.sparkles : LucideIcons.cpu,
                size: 15,
                color: isCurrent ? _PrivateLmTokens.accent : (m.isFree ? _PrivateLmTokens.green : Colors.white60),
              ),
              title: Text(
                m.displayName,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11.5,
                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                  color: Colors.white,
                ),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (m.isFree)
                    Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: _PrivateLmTokens.green.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('FREE', style: TextStyle(color: _PrivateLmTokens.green, fontSize: 9.5, fontWeight: FontWeight.bold)),
                    ),
                  if (isCurrent) const Icon(LucideIcons.check, size: 14, color: _PrivateLmTokens.accent),
                ],
              ),
              onTap: () => _selectAndApplyProviderAndModel(_selectedCloudProviderId, m.id),
            ),
          );
        }),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MODULE 4: ЛОГИ ИНФЕРЕНСА
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildLogsTab() {
    final localState = ref.watch(localAiServiceProvider);
    final nativeState = ref.watch(nativeLlamaServiceProvider);

    final allLogs = [
      if (nativeState.logs.isNotEmpty) ...nativeState.logs.split('\n'),
      if (localState.logs.isNotEmpty) ...localState.logs.split('\n'),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          Row(
            children: [
              Text('Консоль событий и инференса', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: _PrivateLmTokens.muted)),
              const Spacer(),
              IconButton(
                icon: const Icon(LucideIcons.copy, size: 14, color: Colors.white60),
                tooltip: 'Копировать логи',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: allLogs.join('\n')));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Логи скопированы'), duration: Duration(seconds: 1)),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF07080B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _PrivateLmTokens.hairline),
              ),
              child: allLogs.isEmpty
                  ? Center(
                      child: Text(
                        'Логи пока отсутствуют.\nЗапустите модель или отправьте запрос.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.jetBrainsMono(fontSize: 11, color: _PrivateLmTokens.faint),
                      ),
                    )
                  : ListView.builder(
                      itemCount: allLogs.length,
                      itemBuilder: (context, idx) {
                        final line = allLogs[idx];
                        final isErr = line.toLowerCase().contains('err') || line.toLowerCase().contains('fail');
                        return Text(
                          line,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10.5,
                            color: isErr ? _PrivateLmTokens.red : Colors.white70,
                            height: 1.4,
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sliderSetting({
    required String label,
    required String valueStr,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String hint,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white))),
            Text(valueStr, style: GoogleFonts.jetBrainsMono(fontSize: 11, fontWeight: FontWeight.bold, color: _PrivateLmTokens.accent)),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: _PrivateLmTokens.accent,
            inactiveTrackColor: Colors.white12,
            thumbColor: Colors.white,
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
        Text(hint, style: const TextStyle(fontSize: 9.5, color: _PrivateLmTokens.faint)),
      ],
    );
  }
}
