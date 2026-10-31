import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:quantum_ide/core/models/ai_provider_config.dart';
import 'package:quantum_ide/core/services/ai_service.dart';
import 'package:quantum_ide/core/services/local_ai_service.dart';
import 'package:quantum_ide/core/services/native_llama_service.dart';

// ─── Design Tokens (PrivateLM Visual System) ─────────────────────────────────

class _PrivateLmTokens {
  static const bg = Color(0xFF0C0D11);
  static const surface = Color(0xFF14151B);
  static const surfacePressed = Color(0xFF1C1D26);
  static const card = Color(0xFF181A22);
  static const hairline = Color(0x1AFFFFFF);
  static const accent = Color(0xFF00D2FF);
  static const accentPurple = Color(0xFF9D65FF);
  static const text = Colors.white;
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

enum _MainTab { models, settings, logs }
enum _ModelScope { myModels, catalog, cloud }

class _ModelSelectionSheetState extends ConsumerState<ModelSelectionSheet> {
  late _MainTab _mainTab;
  _ModelScope _modelScope = _ModelScope.myModels;
  String _catalogCategory = 'Все';
  String _selectedCloudProviderId = 'privatelm';

  final _searchController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _baseUrlController = TextEditingController();
  final _systemPromptController = TextEditingController();

  // Settings values
  double _temperature = 0.7;
  int _maxTokens = 4096;
  double _topP = 0.95;
  int _cpuThreads = 4;
  int _gpuLayers = 0;
  bool _useFlashAttn = false;

  // Cloud models discovered
  List<DiscoveredModel> _cloudModels = [];
  bool _isDiscovering = false;
  String? _statusMessage;
  bool _statusOk = true;

  @override
  void initState() {
    super.initState();
    _mainTab = widget.initialMainTab == 1
        ? _MainTab.settings
        : (widget.initialMainTab == 2 ? _MainTab.logs : _MainTab.models);

    final aiSvc = ref.read(aiServiceProvider);
    _selectedCloudProviderId = widget.providerId == 'local_edge' ? 'privatelm' : widget.providerId;

    _temperature = aiSvc.temperature;
    _maxTokens = aiSvc.maxTokens;
    _topP = aiSvc.topP;
    _systemPromptController.text = aiSvc.systemPrompt;

    _apiKeyController.text = aiSvc.getApiKey(_selectedCloudProviderId);
    _baseUrlController.text = aiSvc.getBaseUrl(_selectedCloudProviderId);

    final localState = ref.read(localAiServiceProvider);
    _cpuThreads = localState.threads;
    _gpuLayers = localState.gpuLayers;
    _useFlashAttn = localState.useFlashAttn;

    // Load initial discovered models
    _cloudModels = aiSvc.getCachedDiscoveredModels(_selectedCloudProviderId);
    if (_cloudModels.isEmpty) {
      _cloudModels = AiProviders.getRecommendedDiscoveredModels(_selectedCloudProviderId);
    }

    if (widget.providerId == 'local_edge') {
      _modelScope = _ModelScope.myModels;
    } else {
      _modelScope = _ModelScope.cloud;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_selectedCloudProviderId == 'privatelm' || _modelScope == _ModelScope.cloud) {
        _discoverCloudModels();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _apiKeyController.dispose();
    _baseUrlController.dispose();
    _systemPromptController.dispose();
    super.dispose();
  }

  Future<void> _discoverCloudModels() async {
    setState(() {
      _isDiscovering = true;
      _statusMessage = null;
    });

    try {
      final aiSvc = ref.read(aiServiceProvider);
      final models = await aiSvc.discoverModels(
        _selectedCloudProviderId,
        customApiKey: _apiKeyController.text.trim(),
        customBaseUrl: _baseUrlController.text.trim(),
      );

      if (!mounted) return;
      setState(() {
        _cloudModels = models;
        _isDiscovering = false;
        _statusMessage = models.isEmpty
            ? 'Список моделей пуст — проверьте адрес сервера и ключ'
            : 'Доступно моделей: ${models.length}';
        _statusOk = models.isNotEmpty;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isDiscovering = false;
        _statusMessage = 'Ошибка подключения: $e';
        _statusOk = false;
      });
    }
  }

  void _onCloudProviderChanged(String pid) {
    final aiSvc = ref.read(aiServiceProvider);
    setState(() {
      _selectedCloudProviderId = pid;
      _apiKeyController.text = aiSvc.getApiKey(pid);
      _baseUrlController.text = aiSvc.getBaseUrl(pid);
      _cloudModels = aiSvc.getCachedDiscoveredModels(pid);
      if (_cloudModels.isEmpty) {
        _cloudModels = AiProviders.getRecommendedDiscoveredModels(pid);
      }
    });
    aiSvc.setProvider(pid);
    _discoverCloudModels();
  }

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
        ref.read(aiServiceProvider).setProvider('local_edge');
        ref.read(aiServiceProvider).setModel(filename);
        if (mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: Text('⚡ Модель запущена с Vulkan GPU ($gpuLayers слоев)'),
              backgroundColor: const Color(0xFF30D158),
              duration: const Duration(seconds: 2),
            ),
          );
          Navigator.of(context).pop(filename);
        }
        return;
      }
    } catch (e) {
      debugPrint('[NativeLlama] Load error, falling back: $e');
    }

    // Fallback if not loaded via native
    await ref.read(localAiServiceProvider.notifier).selectAndStartModel(filename);
    ref.read(aiServiceProvider).setProvider('local_edge');
    ref.read(aiServiceProvider).setModel(filename);
    if (mounted) {
      Navigator.of(context).pop(filename);
    }
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
        final messenger = ScaffoldMessenger.of(context);
        messenger.showSnackBar(
          SnackBar(content: Text('Файл модели выбран: $name')),
        );
        await _startModelSafely(name, modelPath: path);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка импорта файла: $e')),
      );
    }
  }

  // ─── Main Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.90,
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
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
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
                        'PrivateLM & AI Hub',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'Локальный ИИ, второй телефон и облако',
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

            // Main Segmented Switcher (Модели | Настройки | Логи)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
              child: _buildMainTabs(),
            ),

            const SizedBox(height: 8),

            // Body
            Expanded(
              child: switch (_mainTab) {
                _MainTab.models => _buildModelsTab(),
                _MainTab.settings => _buildSettingsTab(),
                _MainTab.logs => _buildLogsTab(),
              },
            ),
          ],
        ),
      ),
    );
  }

  // ─── Main Tabs Bar ───────────────────────────────────────────────────────

  Widget _buildMainTabs() {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: _PrivateLmTokens.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _PrivateLmTokens.hairline),
      ),
      child: Row(
        children: [
          _mainTabButton(_MainTab.models, 'Модели', LucideIcons.cpu),
          _mainTabButton(_MainTab.settings, 'Настройки', LucideIcons.sliders_horizontal),
          _mainTabButton(_MainTab.logs, 'Логи', LucideIcons.terminal),
        ],
      ),
    );
  }

  Widget _mainTabButton(_MainTab tab, String label, IconData icon) {
    final isSel = _mainTab == tab;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _mainTab = tab),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSel ? Colors.white.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 13, color: isSel ? _PrivateLmTokens.accent : _PrivateLmTokens.muted),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                  color: isSel ? Colors.white : _PrivateLmTokens.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── TAB 1: MODELS (PrivateLM Style) ──────────────────────────────────────

  Widget _buildModelsTab() {
    return Column(
      children: [
        // Sub-scope selector: [ Мои модели | Каталог | Облако & Wi-Fi ]
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                _scopeButton(_ModelScope.myModels, 'Мои модели', LucideIcons.hard_drive),
                _scopeButton(_ModelScope.catalog, 'Каталог', LucideIcons.download),
                _scopeButton(_ModelScope.cloud, 'Облако & Wi-Fi', LucideIcons.cloud),
              ],
            ),
          ),
        ),

        const SizedBox(height: 6),

        // Active Model Banner
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: _buildActiveModelBanner(),
        ),

        // Scope Content
        Expanded(
          child: switch (_modelScope) {
            _ModelScope.myModels => _buildMyModelsScope(),
            _ModelScope.catalog => _buildCatalogScope(),
            _ModelScope.cloud => _buildCloudScope(),
          },
        ),
      ],
    );
  }

  Widget _scopeButton(_ModelScope scope, String label, IconData icon) {
    final isSel = _modelScope == scope;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _modelScope = scope),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isSel ? _PrivateLmTokens.card : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: isSel ? Border.all(color: _PrivateLmTokens.hairline) : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 12, color: isSel ? _PrivateLmTokens.accent : _PrivateLmTokens.faint),
              const SizedBox(width: 5),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 11.5,
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

  // Active Model Banner Widget
  Widget _buildActiveModelBanner() {
    final localState = ref.watch(localAiServiceProvider);
    final aiSvc = ref.watch(aiServiceProvider);
    final nativeLlama = ref.watch(nativeLlamaServiceProvider);

    final isLocalRunning = localState.isRunning || nativeLlama.isModelLoaded;
    final isPrivateLm = aiSvc.selectedProviderId == 'privatelm';

    if (!isLocalRunning && !isPrivateLm) {
      return const SizedBox.shrink();
    }

    final String title;
    final String subtitle;
    final IconData icon;

    if (isPrivateLm) {
      title = aiSvc.selectedModel;
      subtitle = 'Подключено · Второй телефон (PrivateLM Wi-Fi)';
      icon = LucideIcons.smartphone;
    } else {
      title = localState.selectedModelFilename ?? nativeLlama.loadedModelPath?.split('/').last ?? 'Локальная модель';
      subtitle = 'Загружена в память · ${nativeLlama.gpuInfo?.vulkanSupported == true ? "Vulkan GPU" : "CPU ускорение"}';
      icon = LucideIcons.cpu;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _PrivateLmTokens.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _PrivateLmTokens.green.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: _PrivateLmTokens.green,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Icon(icon, size: 16, color: _PrivateLmTokens.green),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(fontSize: 10, color: _PrivateLmTokens.muted),
                ),
              ],
            ),
          ),
          if (isLocalRunning)
            ElevatedButton(
              onPressed: () {
                ref.read(localAiServiceProvider.notifier).stopServer();
                ref.read(nativeLlamaServiceProvider.notifier).unloadModel();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.08),
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                minimumSize: Size.zero,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Выгрузить', style: TextStyle(fontSize: 11)),
            ),
        ],
      ),
    );
  }

  // ── Scope 1: My Models (Downloaded) ──
  Widget _buildMyModelsScope() {
    final localState = ref.watch(localAiServiceProvider);
    final nativeLlama = ref.watch(nativeLlamaServiceProvider);
    final downloadedIds = localState.downloadedModels.entries.where((e) => e.value).map((e) => e.key).toList();

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      children: [
        // Import Button
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _importLocalModelFile,
                icon: const Icon(LucideIcons.file_up, size: 14, color: _PrivateLmTokens.accent),
                label: const Text('Импортировать .gguf с телефона', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: _PrivateLmTokens.hairline),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        if (downloadedIds.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.download, size: 36, color: _PrivateLmTokens.faint),
                const SizedBox(height: 12),
                Text(
                  'На телефоне пока нет скачанных моделей',
                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                ),
                const SizedBox(height: 6),
                Text(
                  'Скачайте готовую модель во вкладке «Каталог» или импортируйте свой .gguf файл.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(fontSize: 12, color: _PrivateLmTokens.muted),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => setState(() => _modelScope = _ModelScope.catalog),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _PrivateLmTokens.accent,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Перейти в каталог моделей', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
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
                description: 'Пользовательская локальная модель',
                filename: id,
                sizeGb: 1.0,
                ramRequiredGb: 2.0,
                url: '',
                engine: LocalAiEngine.llamaServer,
              ),
            );

            final isRunning = (nativeLlama.isModelLoaded && (nativeLlama.loadedModelPath?.contains(model.filename) ?? false)) ||
                (localState.selectedModelFilename == model.filename && localState.isRunning);

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _PrivateLmTokens.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: isRunning ? _PrivateLmTokens.green.withValues(alpha: 0.4) : _PrivateLmTokens.hairline),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(LucideIcons.cpu, size: 18, color: Colors.white70),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          model.name,
                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${model.sizeGb.toStringAsFixed(1)} GB · Контекст 32K · GGUF',
                          style: GoogleFonts.inter(fontSize: 11, color: _PrivateLmTokens.muted),
                        ),
                      ],
                    ),
                  ),
                  if (isRunning)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: _PrivateLmTokens.green.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('Активна', style: TextStyle(fontSize: 11, color: _PrivateLmTokens.green, fontWeight: FontWeight.bold)),
                    )
                  else
                    ElevatedButton(
                      onPressed: () => _startModelSafely(model.filename),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _PrivateLmTokens.accent,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        minimumSize: Size.zero,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('Запустить', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  IconButton(
                    icon: const Icon(LucideIcons.trash_2, size: 14, color: Colors.white38),
                    onPressed: () => ref.read(localAiServiceProvider.notifier).deleteModel(model.id),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  // ── Scope 2: Catalog (Download from PrivateLM) ──
  Widget _buildCatalogScope() {
    final localState = ref.watch(localAiServiceProvider);
    final categories = ['Все', 'Кодинг', 'Рассуждения', 'Vision', 'Без цензуры'];

    final filtered = availableLocalModels.where((m) {
      if (_catalogCategory == 'Кодинг') return m.name.toLowerCase().contains('coder');
      if (_catalogCategory == 'Рассуждения') return m.name.toLowerCase().contains('r1') || m.description.contains('<think>');
      if (_catalogCategory == 'Vision') return m.name.toLowerCase().contains('vl') || m.name.toLowerCase().contains('vision');
      if (_catalogCategory == 'Без цензуры') return m.name.toLowerCase().contains('uncensored');
      return true;
    }).toList();

    return Column(
      children: [
        // Category Pills
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
          child: Row(
            children: categories.map((cat) {
              final isSel = _catalogCategory == cat;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(cat, style: TextStyle(fontSize: 11, color: isSel ? Colors.black : Colors.white70)),
                  selected: isSel,
                  selectedColor: _PrivateLmTokens.accent,
                  backgroundColor: _PrivateLmTokens.surface,
                  onSelected: (_) => setState(() => _catalogCategory = cat),
                ),
              );
            }).toList(),
          ),
        ),

        const SizedBox(height: 6),

        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
            itemCount: filtered.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final model = filtered[index];
              final isDownloaded = localState.downloadedModels[model.id] == true;
              final isDownloading = localState.downloadingModelId == model.id;

              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _PrivateLmTokens.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _PrivateLmTokens.hairline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            model.name,
                            style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700, color: Colors.white),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${model.sizeGb.toStringAsFixed(1)} GB',
                            style: GoogleFonts.jetBrainsMono(fontSize: 10, color: _PrivateLmTokens.accent),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      model.description,
                      style: GoogleFonts.inter(fontSize: 11.5, color: _PrivateLmTokens.muted, height: 1.35),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Text(
                          'Требует ~${model.ramRequiredGb.toStringAsFixed(1)} GB RAM',
                          style: GoogleFonts.inter(fontSize: 10.5, color: _PrivateLmTokens.faint),
                        ),
                        const Spacer(),
                        if (isDownloading) ...[
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _PrivateLmTokens.accent,
                              value: localState.downloadProgress > 0 ? localState.downloadProgress : null,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${(localState.downloadProgress * 100).toStringAsFixed(0)}%',
                            style: GoogleFonts.jetBrainsMono(fontSize: 11, color: _PrivateLmTokens.accent),
                          ),
                        ] else if (isDownloaded) ...[
                          ElevatedButton.icon(
                            onPressed: () => _startModelSafely(model.filename),
                            icon: const Icon(LucideIcons.play, size: 12),
                            label: const Text('Запустить', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _PrivateLmTokens.green,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              minimumSize: Size.zero,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ] else ...[
                          ElevatedButton.icon(
                            onPressed: () {
                              ref.read(localAiServiceProvider.notifier).downloadModel(model.id);
                            },
                            icon: const Icon(LucideIcons.download, size: 12),
                            label: Text('Скачать (${model.sizeGb.toStringAsFixed(1)} GB)', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white.withValues(alpha: 0.1),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              minimumSize: Size.zero,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ],
                      ],
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

  // ── Scope 3: Cloud & Wi-Fi (PrivateLM) ──
  Widget _buildCloudScope() {
    final aiSvc = ref.watch(aiServiceProvider);
    final isPrivateLm = _selectedCloudProviderId == 'privatelm';

    final providers = [
      AiProviders.privatelm,
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

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      children: [
        // Provider Horizontal Selector
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: providers.map((p) {
              final isSel = p.id == _selectedCloudProviderId;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text('${p.logoEmoji} ${p.displayName}',
                      style: TextStyle(fontSize: 11, fontWeight: isSel ? FontWeight.bold : FontWeight.normal, color: isSel ? Colors.black : Colors.white70)),
                  selected: isSel,
                  selectedColor: isSel && p.id == 'privatelm' ? _PrivateLmTokens.accent : Colors.white,
                  backgroundColor: _PrivateLmTokens.surface,
                  onSelected: (_) => _onCloudProviderChanged(p.id),
                ),
              );
            }).toList(),
          ),
        ),

        const SizedBox(height: 12),

        // Config Card for Selected Provider
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _PrivateLmTokens.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isPrivateLm ? _PrivateLmTokens.accent.withValues(alpha: 0.3) : _PrivateLmTokens.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(isPrivateLm ? LucideIcons.smartphone : LucideIcons.key_round, size: 16, color: _PrivateLmTokens.accent),
                  const SizedBox(width: 8),
                  Text(
                    isPrivateLm ? 'Подключение к PrivateLM (Второй телефон)' : 'Настройки API провайдера',
                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Server URL (for PrivateLM or custom)
              if (isPrivateLm || _selectedCloudProviderId == 'custom') ...[
                const Text('Wi-Fi URL сервера:', style: TextStyle(fontSize: 10.5, color: _PrivateLmTokens.muted)),
                const SizedBox(height: 4),
                TextField(
                  controller: _baseUrlController,
                  style: GoogleFonts.jetBrainsMono(fontSize: 12, color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'http://10.109.133.237:8080/v1',
                    hintStyle: const TextStyle(fontSize: 11, color: Colors.white24),
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
              ],

              // API Key
              const Text('API Ключ:', style: TextStyle(fontSize: 10.5, color: _PrivateLmTokens.muted)),
              const SizedBox(height: 4),
              TextField(
                controller: _apiKeyController,
                obscureText: true,
                style: GoogleFonts.jetBrainsMono(fontSize: 12, color: Colors.white),
                decoration: InputDecoration(
                  hintText: isPrivateLm ? 'aichat_...' : 'sk-... или ключ',
                  hintStyle: const TextStyle(fontSize: 11, color: Colors.white24),
                  filled: true,
                  fillColor: Colors.black26,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  isDense: true,
                ),
              ),

              const SizedBox(height: 12),

              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: () async {
                      final key = _apiKeyController.text.trim();
                      final url = _baseUrlController.text.trim();
                      await aiSvc.setApiKey(_selectedCloudProviderId, key);
                      if (url.isNotEmpty) {
                        await aiSvc.setBaseUrl(_selectedCloudProviderId, url);
                      }
                      _discoverCloudModels();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Параметры сохранены'), duration: Duration(seconds: 1)),
                        );
                      }
                    },
                    icon: _isDiscovering
                        ? const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.black))
                        : const Icon(LucideIcons.check, size: 12),
                    label: const Text('Сохранить и проверить', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _PrivateLmTokens.accent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      minimumSize: Size.zero,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  if (_statusMessage != null) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _statusMessage!,
                        style: GoogleFonts.inter(fontSize: 10.5, color: _statusOk ? _PrivateLmTokens.green : _PrivateLmTokens.orange),
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

        const SizedBox(height: 14),

        Text(
          'Доступные модели на ${_selectedCloudProviderId.toUpperCase()}:',
          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: _PrivateLmTokens.muted),
        ),
        const SizedBox(height: 8),

        ..._cloudModels.map((m) {
          final isCurrent = aiSvc.selectedModel == m.id && aiSvc.selectedProviderId == _selectedCloudProviderId;

          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              color: isCurrent ? _PrivateLmTokens.accent.withValues(alpha: 0.12) : _PrivateLmTokens.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isCurrent ? _PrivateLmTokens.accent.withValues(alpha: 0.4) : _PrivateLmTokens.hairline),
            ),
            child: ListTile(
              dense: true,
              leading: Icon(
                m.id == 'default' ? LucideIcons.sparkles : LucideIcons.cpu,
                size: 16,
                color: isCurrent ? _PrivateLmTokens.accent : Colors.white60,
              ),
              title: Text(
                m.displayName,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                  color: isCurrent ? Colors.white : Colors.white.withValues(alpha: 0.9),
                ),
              ),
              trailing: isCurrent ? const Icon(LucideIcons.check, size: 14, color: _PrivateLmTokens.accent) : null,
              onTap: () {
                aiSvc.setProvider(_selectedCloudProviderId);
                aiSvc.setModel(m.id);
                Navigator.of(context).pop(m.id);
              },
            ),
          );
        }),
      ],
    );
  }

  // ─── TAB 2: SETTINGS (PrivateLM Style) ────────────────────────────────────

  Widget _buildSettingsTab() {
    final aiSvc = ref.watch(aiServiceProvider);
    final localState = ref.watch(localAiServiceProvider);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      children: [
        // ── 1. Inference Mode ──
        _sectionLabel('Режим работы (Inference Mode)'),
        Container(
          decoration: BoxDecoration(
            color: _PrivateLmTokens.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _PrivateLmTokens.hairline),
          ),
          child: Column(
            children: [
              _modeRow(
                title: 'Второй телефон (PrivateLM Wi-Fi)',
                subtitle: 'Вычисления идут на втором устройстве по локальной сети',
                icon: LucideIcons.smartphone,
                isSelected: aiSvc.selectedProviderId == 'privatelm',
                onTap: () {
                  aiSvc.setProvider('privatelm');
                  setState(() => _selectedCloudProviderId = 'privatelm');
                },
              ),
              const Divider(color: _PrivateLmTokens.hairline, height: 1),
              _modeRow(
                title: 'Локальный на этом телефоне (Vulkan / CPU)',
                subtitle: 'GGUF модели работают автономно без интернета',
                icon: LucideIcons.cpu,
                isSelected: aiSvc.selectedProviderId == 'local_edge',
                onTap: () {
                  aiSvc.setProvider('local_edge');
                },
              ),
              const Divider(color: _PrivateLmTokens.hairline, height: 1),
              _modeRow(
                title: 'Облачные API (OpenRouter, DeepSeek, Google)',
                subtitle: 'Генерация через официальные облачные ключи',
                icon: LucideIcons.cloud,
                isSelected: aiSvc.selectedProviderId != 'privatelm' && aiSvc.selectedProviderId != 'local_edge',
                onTap: () {
                  aiSvc.setProvider('openrouter');
                  setState(() => _selectedCloudProviderId = 'openrouter');
                },
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // ── 2. Model Parameters ──
        _sectionLabel('Параметры генерации (Model Parameters)'),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _PrivateLmTokens.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _PrivateLmTokens.hairline),
          ),
          child: Column(
            children: [
              // Temperature
              _sliderSetting(
                label: 'Температура (Temperature)',
                valueStr: _temperature.toStringAsFixed(2),
                value: _temperature,
                min: 0.0,
                max: 1.5,
                divisions: 15,
                hint: '0.2 = точно для кода · 0.7 = баланс · 1.0+ = креативно',
                onChanged: (v) {
                  setState(() => _temperature = v);
                  aiSvc.setTemperature(v);
                },
              ),
              const Divider(color: _PrivateLmTokens.hairline, height: 24),
              // Max Tokens
              _sliderSetting(
                label: 'Длина ответа (Max Tokens)',
                valueStr: '$_maxTokens токенов',
                value: _maxTokens.toDouble(),
                min: 512,
                max: 8192,
                divisions: 15,
                hint: 'Ограничение токенов в одном ответе',
                onChanged: (v) {
                  setState(() => _maxTokens = v.toInt());
                  aiSvc.setMaxTokens(v.toInt());
                },
              ),
              const Divider(color: _PrivateLmTokens.hairline, height: 24),
              // Top-P
              _sliderSetting(
                label: 'Креативность (Top-P)',
                valueStr: _topP.toStringAsFixed(2),
                value: _topP,
                min: 0.1,
                max: 1.0,
                divisions: 9,
                hint: 'Порог вероятностной фильтрации',
                onChanged: (v) {
                  setState(() => _topP = v);
                  aiSvc.setTopP(v);
                },
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // ── 3. System Prompt ──
        _sectionLabel('Системная инструкция (System Prompt)'),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _PrivateLmTokens.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _PrivateLmTokens.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _systemPromptController,
                maxLines: 4,
                style: GoogleFonts.inter(fontSize: 12.5, color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Задайте общую роль для ассистента...',
                  hintStyle: TextStyle(fontSize: 12, color: Colors.white24),
                  border: InputBorder.none,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _presetPromptChip('Стандарт', 'You are a helpful AI coding assistant.'),
                  const SizedBox(width: 6),
                  _presetPromptChip('Fullstack Ninja', 'You are an elite Senior Fullstack Architect. Write concise, production-ready code.'),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: () {
                      aiSvc.setSystemPrompt(_systemPromptController.text.trim());
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Системный промт сохранён'), duration: Duration(seconds: 1)),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _PrivateLmTokens.accent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      minimumSize: Size.zero,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Сохранить', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // ── 4. Hardware & Performance (Vulkan GPU & CPU) ──
        _sectionLabel('Аппаратные настройки локального движка'),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _PrivateLmTokens.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _PrivateLmTokens.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sliderSetting(
                label: 'Потоки процессора (CPU Threads)',
                valueStr: '$_cpuThreads потоков',
                value: _cpuThreads.toDouble(),
                min: 1,
                max: 8,
                divisions: 7,
                hint: 'Рекомендуется: 3–6 потоков для баланса скорости и нагрева',
                onChanged: (v) {
                  setState(() => _cpuThreads = v.toInt());
                  ref.read(localAiServiceProvider.notifier).updateSettings(threads: v.toInt());
                },
              ),
              const Divider(color: _PrivateLmTokens.hairline, height: 24),
              _sliderSetting(
                label: 'Слои ускорения GPU / Vulkan',
                valueStr: _gpuLayers == 0 ? '0 (Чистый CPU)' : '$_gpuLayers слоёв',
                value: _gpuLayers.toDouble(),
                min: 0,
                max: 33,
                divisions: 33,
                hint: '0 = безопасно на CPU · 16–33 = аппаратный Vulkan GPU',
                onChanged: (v) {
                  setState(() => _gpuLayers = v.toInt());
                  ref.read(localAiServiceProvider.notifier).updateSettings(gpuLayers: v.toInt());
                },
              ),
              const Divider(color: _PrivateLmTokens.hairline, height: 24),
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Flash Attention', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
                        Text('Снижает расход памяти при длинном контексте', style: TextStyle(fontSize: 10.5, color: _PrivateLmTokens.muted)),
                      ],
                    ),
                  ),
                  Switch(
                    value: _useFlashAttn,
                    activeColor: _PrivateLmTokens.accent,
                    onChanged: (v) {
                      setState(() => _useFlashAttn = v);
                      ref.read(localAiServiceProvider.notifier).updateSettings(useFlashAttn: v);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 30),
      ],
    );
  }

  Widget _modeRow({required String title, required String subtitle, required IconData icon, required bool isSelected, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isSelected ? _PrivateLmTokens.accent.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 16, color: isSelected ? _PrivateLmTokens.accent : Colors.white60),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GoogleFonts.inter(fontSize: 12.5, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500, color: Colors.white)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: GoogleFonts.inter(fontSize: 10.5, color: _PrivateLmTokens.muted)),
                ],
              ),
            ),
            if (isSelected) const Icon(LucideIcons.check, size: 16, color: _PrivateLmTokens.accent),
          ],
        ),
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
            Expanded(child: Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white))),
            Text(valueStr, style: GoogleFonts.jetBrainsMono(fontSize: 11.5, fontWeight: FontWeight.bold, color: _PrivateLmTokens.accent)),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: _PrivateLmTokens.accent,
            inactiveTrackColor: Colors.white12,
            thumbColor: Colors.white,
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
        Text(hint, style: const TextStyle(fontSize: 10, color: _PrivateLmTokens.faint)),
      ],
    );
  }

  Widget _presetPromptChip(String title, String prompt) {
    return ActionChip(
      label: Text(title, style: const TextStyle(fontSize: 10, color: Colors.white70)),
      backgroundColor: Colors.white.withValues(alpha: 0.06),
      padding: EdgeInsets.zero,
      onPressed: () => _systemPromptController.text = prompt,
    );
  }

  Widget _sectionLabel(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: _PrivateLmTokens.muted),
      ),
    );
  }

  // ─── TAB 3: LOGS (PrivateLM Style) ────────────────────────────────────────

  Widget _buildLogsTab() {
    final localState = ref.watch(localAiServiceProvider);
    final nativeState = ref.watch(nativeLlamaServiceProvider);

    final allLogs = [
      if (nativeState.logs.isNotEmpty) ...nativeState.logs.split('\n'),
      if (localState.logs.isNotEmpty) ...localState.logs.split('\n'),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                'Консоль событий и инференса',
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: _PrivateLmTokens.muted),
              ),
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
                borderRadius: BorderRadius.circular(14),
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
}
