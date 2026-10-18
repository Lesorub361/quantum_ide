import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:quantum_ide/core/models/ai_provider_config.dart';
import 'package:quantum_ide/core/models/local_model_metadata.dart';
import 'package:quantum_ide/core/services/ai_service.dart';
import 'package:quantum_ide/core/services/local_ai_service.dart';
import 'package:quantum_ide/core/services/model_catalog_service.dart';
import 'package:quantum_ide/core/services/hugging_face_hub_service.dart';

enum MainHubTab { models, settings, logs }
enum LocalViewMode { catalog, huggingFaceOnline, ollamaLibrary, downloaded, cloud }

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

class _ModelSelectionSheetState extends ConsumerState<ModelSelectionSheet> {
  late MainHubTab _mainTab;
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _hfSearchController = TextEditingController();
  final TextEditingController _ollamaPullController = TextEditingController();
  final TextEditingController _systemPromptController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _baseUrlController = TextEditingController();

  List<DiscoveredModel> _models = [];
  bool _isDiscovering = false;
  String? _statusMessage;
  bool _statusOk = true;
  String _selectedCategory = 'Все';
  LocalViewMode _localViewMode = LocalViewMode.catalog;

  // Hugging Face online search state
  List<HfModelItem> _hfResults = [];
  bool _isSearchingHf = false;
  String? _expandedHfRepoId;
  final Map<String, List<HfGgufFile>> _hfRepoFiles = {};
  bool _isLoadingHfFiles = false;

  // Settings state
  late String _settingsProviderId;
  late double _temperature;
  late int _maxTokens;
  late double _topP;
  late int _localThreads;
  late int _localGpuLayers;
  late bool _localUseFlashAttn;

  bool get _isLocalProvider =>
      widget.providerId == 'local_edge' || widget.providerId == 'ollama';

  @override
  void initState() {
    super.initState();
    _mainTab = widget.initialMainTab == 1
        ? MainHubTab.settings
        : (widget.initialMainTab == 2 ? MainHubTab.logs : MainHubTab.models);

    final aiSvc = ref.read(aiServiceProvider);
    _models = aiSvc.getCachedDiscoveredModels(widget.providerId);
    if (_models.isEmpty) {
      _models = AiProviders.getRecommendedDiscoveredModels(widget.providerId);
    }

    _settingsProviderId = widget.providerId;
    _temperature = aiSvc.temperature;
    _maxTokens = aiSvc.maxTokens;
    _topP = aiSvc.topP;
    _systemPromptController.text = aiSvc.systemPrompt;
    _apiKeyController.text = aiSvc.getApiKey(_settingsProviderId);
    _baseUrlController.text = aiSvc.getBaseUrl(_settingsProviderId);

    final localState = ref.read(localAiServiceProvider);
    _localThreads = localState.threads;
    _localGpuLayers = localState.gpuLayers;
    _localUseFlashAttn = localState.useFlashAttn;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _hfSearchController.dispose();
    _ollamaPullController.dispose();
    _systemPromptController.dispose();
    _apiKeyController.dispose();
    _baseUrlController.dispose();
    super.dispose();
  }

  Future<void> _searchHuggingFace(String query) async {
    setState(() {
      _isSearchingHf = true;
      _statusMessage = null;
    });

    try {
      final hfSvc = ref.read(huggingFaceHubServiceProvider);
      final results = await hfSvc.searchGgufModels(query);
      setState(() {
        _hfResults = results;
        _isSearchingHf = false;
        if (results.isEmpty) {
          _statusMessage = 'По запросу "$query" не найдено GGUF моделей на Hugging Face';
          _statusOk = false;
        }
      });
    } catch (e) {
      setState(() {
        _isSearchingHf = false;
        _statusMessage = 'Ошибка поиска на Hugging Face: $e';
        _statusOk = false;
      });
    }
  }

  Future<void> _loadHfRepoFiles(String repoId) async {
    if (_hfRepoFiles.containsKey(repoId)) {
      setState(() => _expandedHfRepoId = _expandedHfRepoId == repoId ? null : repoId);
      return;
    }

    setState(() {
      _expandedHfRepoId = repoId;
      _isLoadingHfFiles = true;
    });

    try {
      final hfSvc = ref.read(huggingFaceHubServiceProvider);
      final files = await hfSvc.fetchRepoGgufFiles(repoId);
      setState(() {
        _hfRepoFiles[repoId] = files;
        _isLoadingHfFiles = false;
      });
    } catch (_) {
      setState(() => _isLoadingHfFiles = false);
    }
  }

  Future<void> _discover() async {
    setState(() {
      _isDiscovering = true;
      _statusMessage = null;
    });

    try {
      final aiSvc = ref.read(aiServiceProvider);
      final models = await aiSvc.discoverModels(
        widget.providerId,
        customApiKey: widget.apiKey,
        customBaseUrl: widget.baseUrl,
      );

      setState(() {
        _models = models;
        _isDiscovering = false;
        _statusMessage = 'Обнаружено ${models.length} моделей';
        _statusOk = true;
      });
    } catch (e) {
      setState(() {
        _isDiscovering = false;
        _statusMessage = 'Ошибка обнаружения: $e';
        _statusOk = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final localAiState = ref.watch(localAiServiceProvider);

    return Container(
      height: MediaQuery.of(context).size.height * 0.90,
      decoration: const BoxDecoration(
        color: Color(0xFF10121A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: Colors.white12, width: 1)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 8, bottom: 4),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header: Title, Active status & Close
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                ShaderMask(
                  shaderCallback: (b) => const LinearGradient(
                    colors: [Colors.cyanAccent, Colors.purpleAccent],
                  ).createShader(b),
                  child: const Icon(LucideIcons.sparkles, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 8),
                Text(
                  'Quantum AI Hub',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                // Live Status Badge
                _buildLiveStatusPill(localAiState),
                const Spacer(),
                IconButton(
                  icon: const Icon(LucideIcons.x, size: 18, color: Colors.white54),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ],
            ),
          ),

          // Main Hub Tabs Navigation (Модели / Настройки / Логи)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                children: [
                  _mainTabButton(MainHubTab.models, '🤖 Модели', LucideIcons.cpu),
                  _mainTabButton(MainHubTab.settings, '⚙️ Настройки', LucideIcons.sliders_horizontal),
                  _mainTabButton(MainHubTab.logs, '📋 Логи & Статус', LucideIcons.terminal),
                ],
              ),
            ),
          ),

          const Divider(color: Colors.white10, height: 10),

          // Body depending on MainTab
          Expanded(
            child: _buildMainTabBody(context, query, localAiState),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveStatusPill(LocalAiState localState) {
    if (_isLocalProvider) {
      if (localState.isStarting) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
          decoration: BoxDecoration(
            color: Colors.amber.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(width: 8, height: 8, child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.amberAccent)),
              const SizedBox(width: 5),
              Text('Загрузка в RAM...', style: GoogleFonts.inter(fontSize: 10, color: Colors.amberAccent, fontWeight: FontWeight.bold)),
            ],
          ),
        );
      } else if (localState.isRunning) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
          decoration: BoxDecoration(
            color: Colors.greenAccent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 6, height: 6, decoration: const BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle)),
              const SizedBox(width: 5),
              Text('Готова к работе', style: GoogleFonts.inter(fontSize: 10, color: Colors.greenAccent, fontWeight: FontWeight.bold)),
            ],
          ),
        );
      } else if (localState.error != null) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
          decoration: BoxDecoration(
            color: Colors.redAccent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
          ),
          child: Text('Ошибка запуска', style: GoogleFonts.inter(fontSize: 10, color: Colors.redAccent, fontWeight: FontWeight.bold)),
        );
      } else {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text('Остановлена', style: GoogleFonts.inter(fontSize: 10, color: Colors.white60)),
        );
      }
    } else {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
        decoration: BoxDecoration(
          color: Colors.blueAccent.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.4)),
        ),
        child: Text('Облачный API', style: GoogleFonts.inter(fontSize: 10, color: Colors.blueAccent, fontWeight: FontWeight.bold)),
      );
    }
  }

  Widget _mainTabButton(MainHubTab tab, String label, IconData icon) {
    final isSelected = _mainTab == tab;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _mainTab = tab),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? Colors.cyanAccent : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 12, color: isSelected ? Colors.black : Colors.white70),
              const SizedBox(width: 5),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? Colors.black : Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainTabBody(BuildContext context, String query, LocalAiState localAiState) {
    switch (_mainTab) {
      case MainHubTab.models:
        return _buildModelsTabBody(context, query);
      case MainHubTab.settings:
        return _buildUnifiedSettingsView(context, localAiState);
      case MainHubTab.logs:
        return _buildLogsView(context, localAiState);
    }
  }

  // ─── 1. Models Tab Body ──────────────────────────────────────────────────
  Widget _buildModelsTabBody(BuildContext context, String query) {
    return Column(
      children: [
        // Local Mode Selector Tabs
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _subTabButton(LocalViewMode.catalog, '🔥 Топ каталог', LucideIcons.sparkles),
                const SizedBox(width: 6),
                _subTabButton(LocalViewMode.huggingFaceOnline, '🌐 Hugging Face Hub', LucideIcons.globe),
                const SizedBox(width: 6),
                _subTabButton(LocalViewMode.ollamaLibrary, '🦙 Ollama Library', LucideIcons.terminal),
                const SizedBox(width: 6),
                _subTabButton(LocalViewMode.downloaded, '💾 Скачанные', LucideIcons.hard_drive),
                const SizedBox(width: 6),
                _subTabButton(LocalViewMode.cloud, '☁️ Облачные', LucideIcons.cloud),
              ],
            ),
          ),
        ),

        // Search Box (if in catalog or downloaded or cloud)
        if (_localViewMode == LocalViewMode.catalog || _localViewMode == LocalViewMode.downloaded || _localViewMode == LocalViewMode.cloud)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Поиск модели, параметров, архитектуры...',
                hintStyle: GoogleFonts.inter(color: Colors.white38, fontSize: 12),
                prefixIcon: const Icon(LucideIcons.search, size: 16, color: Colors.white38),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(LucideIcons.x, size: 14, color: Colors.white38),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                isDense: true,
              ),
            ),
          ),

        // Category filter pills for Top catalog
        if (_localViewMode == LocalViewMode.catalog)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
            child: Row(
              children: ['Все', 'Код', 'Рассуждения', 'Чат', 'Зрение'].map((cat) {
                final isSelected = _selectedCategory == cat;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(
                      cat == 'Все'
                          ? 'Все модели'
                          : (cat == 'Код'
                              ? '💻 Кодинг'
                              : (cat == 'Рассуждения'
                                  ? '🧠 Логика (<think>)'
                                  : (cat == 'Чат' ? '💬 Диалог' : '👁️ Зрение'))),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        color: isSelected ? Colors.black : Colors.white70,
                      ),
                    ),
                    selected: isSelected,
                    selectedColor: Colors.cyanAccent,
                    backgroundColor: Colors.white.withValues(alpha: 0.06),
                    onSelected: (_) => setState(() => _selectedCategory = cat),
                  ),
                );
              }).toList(),
            ),
          ),

        // Status message
        if (_statusMessage != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _statusOk
                    ? Colors.cyanAccent.withValues(alpha: 0.08)
                    : Colors.orangeAccent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _statusOk
                      ? Colors.cyanAccent.withValues(alpha: 0.25)
                      : Colors.orangeAccent.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _statusOk ? LucideIcons.info : LucideIcons.triangle_alert,
                    size: 14,
                    color: _statusOk ? Colors.cyanAccent : Colors.orangeAccent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _statusMessage!,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: _statusOk ? Colors.cyanAccent : Colors.orangeAccent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

        const Divider(color: Colors.white10, height: 6),

        Expanded(
          child: _buildCurrentView(context, query),
        ),
      ],
    );
  }

  Widget _subTabButton(LocalViewMode mode, String label, IconData icon) {
    final isSelected = _localViewMode == mode;
    return GestureDetector(
      onTap: () {
        setState(() => _localViewMode = mode);
        if (mode == LocalViewMode.huggingFaceOnline && _hfResults.isEmpty) {
          _searchHuggingFace('');
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? Colors.cyanAccent.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? Colors.cyanAccent : Colors.white12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: isSelected ? Colors.cyanAccent : Colors.white70),
            const SizedBox(width: 5),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? Colors.cyanAccent : Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentView(BuildContext context, String query) {
    switch (_localViewMode) {
      case LocalViewMode.catalog:
        return _buildCatalogView(context, query);
      case LocalViewMode.huggingFaceOnline:
        return _buildHuggingFaceOnlineView(context);
      case LocalViewMode.ollamaLibrary:
        return _buildOllamaLibraryView(context);
      case LocalViewMode.downloaded:
        return _buildDownloadedView(context, query);
      case LocalViewMode.cloud:
        return _buildCloudModelsList(context, query);
    }
  }

  // ─── 2. Top Catalog View ─────────────────────────────────────────────────
  Widget _buildCatalogView(BuildContext context, String query) {
    final catalogState = ref.watch(modelCatalogProvider);
    final localAiState = ref.watch(localAiServiceProvider);
    final activeFilename = localAiState.selectedModelFilename;

    final catalogModels = LocalModelMetadata.catalog.where((meta) {
      final matchesQuery = query.isEmpty ||
          meta.name.toLowerCase().contains(query) ||
          meta.filename.toLowerCase().contains(query) ||
          meta.capabilities.toLowerCase().contains(query) ||
          meta.category.toLowerCase().contains(query);
      if (!matchesQuery) return false;

      if (_selectedCategory == 'Все') return true;
      if (_selectedCategory == 'Код') return meta.category == 'Код';
      if (_selectedCategory == 'Рассуждения') return meta.category == 'Рассуждения';
      if (_selectedCategory == 'Чат') return meta.category == 'Чат';
      if (_selectedCategory == 'Зрение') return meta.category == 'Зрение';
      return true;
    }).toList();

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      itemCount: catalogModels.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final model = catalogModels[index];
        final isDownloaded = catalogState.downloadedModels[model.filename] == true ||
            localAiState.downloadedModels[model.filename] == true;
        final isSelected = activeFilename == model.filename;
        final downloadInfo = catalogState.downloads[model.filename];
        final isDownloading = downloadInfo != null && downloadInfo.status == DownloadStatus.downloading;

        return _buildCatalogCard(context, model, isDownloaded, isSelected, isDownloading, downloadInfo);
      },
    );
  }

  Widget _buildCatalogCard(
    BuildContext context,
    LocalModelMetadata model,
    bool isDownloaded,
    bool isSelected,
    bool isDownloading,
    ModelDownloadInfo? downloadInfo,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isSelected
            ? const Color(0xFF1E2838)
            : const Color(0xFF161822),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected
              ? Colors.cyanAccent.withValues(alpha: 0.6)
              : Colors.white.withValues(alpha: 0.08),
          width: isSelected ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  model.name,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.bold,
                    fontSize: 13.5,
                    color: Colors.white,
                  ),
                ),
              ),
              if (isSelected)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.cyanAccent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('АКТИВНАЯ', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.cyanAccent)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            model.capabilities,
            style: const TextStyle(fontSize: 11.5, color: Colors.white70),
          ),
          const SizedBox(height: 8),

          // Badges: Context, Speed, RAM, Quant
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _infoBadge(LucideIcons.file_text, model.contextWindow, Colors.purpleAccent),
              _infoBadge(LucideIcons.zap, model.speedEstimate, Colors.amberAccent),
              _infoBadge(LucideIcons.hard_drive, model.ramRequiredFormatted, Colors.lightGreenAccent),
              _infoBadge(LucideIcons.layers, model.quantization, Colors.cyanAccent),
              _infoBadge(LucideIcons.database, model.sizeFormatted, Colors.white60),
              if (ref.watch(localAiServiceProvider).availableRamMb > 0 &&
                  model.ramRequiredGb * 1024 > ref.watch(localAiServiceProvider).availableRamMb)
                _infoBadge(LucideIcons.triangle_alert, 'Мало RAM', Colors.redAccent),
            ],
          ),

          if (isDownloading && downloadInfo != null) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: downloadInfo.progress > 0 ? downloadInfo.progress : null,
              backgroundColor: Colors.white10,
              color: Colors.cyanAccent,
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${(downloadInfo.progress * 100).toStringAsFixed(1)}% (${ModelCatalogNotifier.formatBytes(downloadInfo.downloadedBytes)} / ${ModelCatalogNotifier.formatBytes(downloadInfo.totalBytes)})',
                  style: const TextStyle(fontSize: 10, color: Colors.white60),
                ),
                Text(
                  ModelCatalogNotifier.formatSpeed(downloadInfo.speed),
                  style: const TextStyle(fontSize: 10, color: Colors.cyanAccent, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],

          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (isDownloaded) ...[
                ElevatedButton.icon(
                  onPressed: () async {
                    await ref.read(localAiServiceProvider.notifier).selectAndStartModel(model.filename);
                    if (!context.mounted) return;
                    Navigator.pop(context, model.filename);
                  },
                  icon: const Icon(LucideIcons.play, size: 12),
                  label: const Text('Запустить сейчас'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.cyanAccent,
                    foregroundColor: Colors.black,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  ),
                ),
              ] else if (isDownloading) ...[
                OutlinedButton.icon(
                  onPressed: () {
                    ref.read(modelCatalogProvider.notifier).cancelDownload(model.filename);
                  },
                  icon: const Icon(LucideIcons.x, size: 12, color: Colors.redAccent),
                  label: const Text('Отмена', style: TextStyle(color: Colors.redAccent, fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    side: const BorderSide(color: Colors.redAccent),
                  ),
                ),
              ] else ...[
                ElevatedButton.icon(
                  onPressed: () {
                    final catModel = AiCatalogModel(
                      id: model.id,
                      name: model.name,
                      filename: model.filename,
                      url: model.url,
                      size: model.sizeFormatted,
                      description: model.capabilities,
                      category: ModelCategory.text,
                      runtime: ModelRuntime.llama,
                    );
                    ref.read(modelCatalogProvider.notifier).downloadModel(catModel);
                  },
                  icon: const Icon(LucideIcons.download, size: 12),
                  label: Text('Скачать (${model.sizeFormatted})'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.1),
                    foregroundColor: Colors.white,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoBadge(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 4),
          Text(label, style: GoogleFonts.inter(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ─── 3. Downloaded Models View ───────────────────────────────────────────
  Widget _buildDownloadedView(BuildContext context, String query) {
    final catalogState = ref.watch(modelCatalogProvider);
    final localAiState = ref.watch(localAiServiceProvider);
    final activeFilename = localAiState.selectedModelFilename;

    final downloadedFiles = catalogState.downloadedModels.entries
        .where((e) => e.value == true)
        .map((e) => e.key)
        .toList();

    for (final e in localAiState.downloadedModels.entries) {
      if (e.value == true && !downloadedFiles.contains(e.key)) {
        downloadedFiles.add(e.key);
      }
    }

    final filtered = downloadedFiles.where((name) {
      return query.isEmpty || name.toLowerCase().contains(query);
    }).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.hard_drive, size: 38, color: Colors.white24),
            const SizedBox(height: 10),
            Text(
              query.isEmpty ? 'Нет скачанных моделей' : 'Модель не найдена',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 6),
            const Text(
              'Перейдите во вкладку «🔥 Топ каталог» или «🌐 Hugging Face Hub» для загрузки',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      itemCount: filtered.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final filename = filtered[index];
        final isSelected = activeFilename == filename;
        final isRunning = isSelected && localAiState.isRunning;
        final isStarting = isSelected && localAiState.isStarting;

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF1E2838) : const Color(0xFF161822),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? Colors.cyanAccent.withValues(alpha: 0.6) : Colors.white10,
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isRunning ? LucideIcons.circle_check : LucideIcons.cpu,
                    size: 16,
                    color: isRunning ? Colors.greenAccent : (isStarting ? Colors.amberAccent : Colors.cyanAccent),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      filename,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isRunning)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.greenAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('ЗАПУЩЕНА', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.greenAccent)),
                    )
                  else if (isStarting)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('ЗАГРУЗКА В RAM', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.amberAccent)),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(LucideIcons.trash_2, size: 14, color: Colors.redAccent),
                    tooltip: 'Удалить модель с устройства',
                    onPressed: () {
                      ref.read(modelCatalogProvider.notifier).deleteModel(filename);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Модель $filename удалена')),
                      );
                    },
                  ),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          await ref.read(localAiServiceProvider.notifier).selectModel(filename);
                          if (!context.mounted) return;
                          Navigator.pop(context, filename);
                        },
                        icon: const Icon(LucideIcons.check, size: 12),
                        label: const Text('Выбрать', style: TextStyle(fontSize: 11)),
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          foregroundColor: Colors.white70,
                          side: const BorderSide(color: Colors.white24),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () async {
                          await ref.read(localAiServiceProvider.notifier).selectAndStartModel(filename);
                          if (!context.mounted) return;
                          Navigator.pop(context, filename);
                        },
                        icon: const Icon(LucideIcons.play, size: 12),
                        label: Text(isRunning ? 'Перезапустить' : 'Запустить'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.cyanAccent,
                          foregroundColor: Colors.black,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // ─── 4. Live Hugging Face Hub Online Search ───────────────────────────────
  Widget _buildHuggingFaceOnlineView(BuildContext context) {
    return Column(
      children: [
        // HF Search bar & quick filters
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _hfSearchController,
                  onSubmitted: _searchHuggingFace,
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Поиск на Hugging Face (например: phi-4, deepseek, qwen)...',
                    hintStyle: GoogleFonts.inter(color: Colors.white38, fontSize: 12),
                    prefixIcon: const Icon(LucideIcons.search, size: 16, color: Colors.cyanAccent),
                    suffixIcon: IconButton(
                      icon: const Icon(LucideIcons.arrow_right, size: 16, color: Colors.cyanAccent),
                      onPressed: () => _searchHuggingFace(_hfSearchController.text),
                    ),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.05),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Quick Search Tags
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          child: Row(
            children: ['Phi-4', 'DeepSeek-R1', 'Qwen2.5-Coder', 'Llama-3.3', 'Mistral-Nemo', 'SmolLM2', 'Vision'].map((tag) {
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ActionChip(
                  label: Text(tag, style: const TextStyle(fontSize: 10, color: Colors.white70)),
                  backgroundColor: Colors.white.withValues(alpha: 0.06),
                  onPressed: () {
                    _hfSearchController.text = tag;
                    _searchHuggingFace(tag);
                  },
                ),
              );
            }).toList(),
          ),
        ),

        const Divider(color: Colors.white10, height: 8),

        Expanded(
          child: _isSearchingHf
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Colors.cyanAccent),
                      SizedBox(height: 12),
                      Text('Поиск новейших GGUF моделей на Hugging Face Hub...', style: TextStyle(color: Colors.white60, fontSize: 12)),
                    ],
                  ),
                )
              : _hfResults.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.globe, size: 36, color: Colors.white24),
                          SizedBox(height: 10),
                          Text('Введите запрос для поиска любых моделей на Hugging Face', style: TextStyle(color: Colors.white54, fontSize: 12)),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      itemCount: _hfResults.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = _hfResults[index];
                        final isExpanded = _expandedHfRepoId == item.id;
                        final files = _hfRepoFiles[item.id];

                        return Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF161822),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ListTile(
                                dense: true,
                                title: Text(item.name, style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13)),
                                subtitle: Text('${item.author} · ${item.downloads} скачиваний · ${item.likes} ❤️', style: const TextStyle(fontSize: 11, color: Colors.white54)),
                                trailing: IconButton(
                                  icon: Icon(isExpanded ? LucideIcons.chevron_up : LucideIcons.chevron_down, size: 16, color: Colors.cyanAccent),
                                  onPressed: () => _loadHfRepoFiles(item.id),
                                ),
                              ),
                              if (isExpanded) ...[
                                const Divider(color: Colors.white10, height: 1),
                                if (_isLoadingHfFiles && files == null)
                                  const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyanAccent))),
                                  )
                                else if (files == null || files.isEmpty)
                                  const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: Text('GGUF файлы не найдены в репозитории', style: TextStyle(fontSize: 11, color: Colors.white38)),
                                  )
                                else
                                  ...files.map((file) {
                                    return ListTile(
                                      dense: true,
                                      title: Text(file.filename, style: GoogleFonts.jetBrainsMono(fontSize: 11, color: Colors.cyanAccent)),
                                      subtitle: Text('${file.quantization} · ${file.sizeFormatted}', style: const TextStyle(fontSize: 10, color: Colors.white54)),
                                      trailing: ElevatedButton.icon(
                                        onPressed: () async {
                                          final catalogModel = AiCatalogModel(
                                            id: file.filename,
                                            name: file.filename,
                                            filename: file.filename,
                                            url: file.downloadUrl,
                                            size: file.sizeFormatted,
                                            description: 'Загружено с Hugging Face Hub (${item.id})',
                                            category: ModelCategory.text,
                                            runtime: ModelRuntime.llama,
                                          );
                                          await ref.read(modelCatalogProvider.notifier).downloadModel(catalogModel);
                                          if (!context.mounted) return;
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('Загрузка ${file.filename} запущена в фоне!')),
                                          );
                                        },
                                        icon: const Icon(LucideIcons.download, size: 11),
                                        label: const Text('Скачать', style: TextStyle(fontSize: 10)),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.cyanAccent,
                                          foregroundColor: Colors.black,
                                          visualDensity: VisualDensity.compact,
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        ),
                                      ),
                                    );
                                  }),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  // ─── 5. Ollama Library Pull View ──────────────────────────────────────────
  Widget _buildOllamaLibraryView(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListView(
        children: [
          Text(
            'Загрузка любой модели из Ollama Library:',
            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 6),
          const Text(
            'Введите официальный тег модели с ollama.com (например: phi4:14b, deepseek-r1:14b, qwen2.5-coder:7b)',
            style: TextStyle(fontSize: 11, color: Colors.white60),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ollamaPullController,
                  style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'phi4:14b',
                    hintStyle: GoogleFonts.jetBrainsMono(color: Colors.white30, fontSize: 13),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.05),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () async {
                  final tag = _ollamaPullController.text.trim();
                  if (tag.isEmpty) return;
                  final info = LocalModelInfo(
                    id: 'ollama_$tag',
                    name: tag,
                    description: 'Ollama model from library',
                    filename: tag,
                    sizeGb: 2.0,
                    ramRequiredGb: 4.0,
                    url: tag,
                    engine: LocalAiEngine.ollama,
                  );
                  await ref.read(localAiServiceProvider.notifier).downloadModel(info.id);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Загрузка модели $tag через Ollama запущена!')),
                  );
                },
                icon: const Icon(LucideIcons.download, size: 14),
                label: const Text('Pull'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent, foregroundColor: Colors.black),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Популярные новые модели в Ollama:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70)),
          const SizedBox(height: 8),
          ...[
            {'tag': 'phi4:14b', 'desc': 'Microsoft Phi-4 14B (SOTA Reasoning 2025/2026)', 'size': '9.1 GB'},
            {'tag': 'deepseek-r1:14b', 'desc': 'DeepSeek R1 14B (Глубокие рассуждения и логика)', 'size': '9.0 GB'},
            {'tag': 'qwen2.5-coder:14b', 'desc': 'Qwen 2.5 Coder 14B (Топ кодинг модель)', 'size': '9.0 GB'},
            {'tag': 'llama3.3:70b', 'desc': 'Meta Llama 3.3 70B (Флагманский уровень)', 'size': '43 GB'},
            {'tag': 'mistral-nemo:12b', 'desc': 'Mistral NeMo 12B (128K контекст)', 'size': '7.1 GB'},
            {'tag': 'smollm2:1.7b', 'desc': 'SmolLM2 1.7B (Мобильный компакт)', 'size': '1.0 GB'},
            {'tag': 'minicpm-v:8b', 'desc': 'MiniCPM-V 2.6 (Зрение и анализ фото)', 'size': '5.5 GB'},
          ].map((item) {
            return Card(
              color: const Color(0xFF181B26),
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                dense: true,
                title: Text(item['tag']!, style: GoogleFonts.jetBrainsMono(fontWeight: FontWeight.bold, color: Colors.cyanAccent, fontSize: 12)),
                subtitle: Text('${item['desc']!} · ${item['size']!}', style: const TextStyle(fontSize: 11, color: Colors.white60)),
                trailing: IconButton(
                  icon: const Icon(LucideIcons.download, size: 16, color: Colors.cyanAccent),
                  onPressed: () {
                    _ollamaPullController.text = item['tag']!;
                  },
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  // ─── 6. Cloud Models List ────────────────────────────────────────────────
  Widget _buildCloudModelsList(BuildContext context, String query) {
    final filteredModels = query.isEmpty
        ? _models
        : _models.where((m) {
            return m.id.toLowerCase().contains(query) ||
                m.displayName.toLowerCase().contains(query);
          }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Облачные модели (${filteredModels.length}):',
                style: const TextStyle(fontSize: 11, color: Colors.white54, fontWeight: FontWeight.bold),
              ),
              TextButton.icon(
                onPressed: _isDiscovering ? null : _discover,
                icon: const Icon(LucideIcons.refresh_cw, size: 11, color: Colors.cyanAccent),
                label: const Text('Обновить список', style: TextStyle(fontSize: 10, color: Colors.cyanAccent)),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            itemCount: filteredModels.length,
            separatorBuilder: (_, _) => const SizedBox(height: 6),
            itemBuilder: (context, index) {
              final model = filteredModels[index];
              final isSelected = model.id == widget.currentModel;
              return Container(
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF1E2838) : const Color(0xFF161822),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: isSelected ? Colors.cyanAccent : Colors.white10),
                ),
                child: ListTile(
                  dense: true,
                  title: Text(
                    model.displayName,
                    style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: isSelected ? Colors.cyanAccent : Colors.white),
                  ),
                  subtitle: Text(
                    model.id,
                    style: GoogleFonts.jetBrainsMono(fontSize: 11, color: Colors.white54),
                  ),
                  trailing: isSelected
                      ? const Icon(LucideIcons.circle_check, size: 18, color: Colors.cyanAccent)
                      : const Icon(LucideIcons.chevron_right, size: 16, color: Colors.white24),
                  onTap: () => Navigator.pop(context, model.id),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ─── 7. Unified Settings View (FOR ALL MODELS) ───────────────────────────
  Widget _buildUnifiedSettingsView(BuildContext context, LocalAiState localAiState) {
    final aiSvc = ref.read(aiServiceProvider);

    String tempDesc;
    if (_temperature < 0.4) {
      tempDesc = 'Точный код & Строгие факты';
    } else if (_temperature <= 0.8) {
      tempDesc = 'Сбалансированный режим (Рекомендуется)';
    } else {
      tempDesc = 'Креативный брейншторминг & Идеи';
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      children: [
        // Section A: Generation Parameters
        _settingsSectionHeader('Параметры генерации для всех моделей', LucideIcons.sliders_horizontal),
        const SizedBox(height: 10),

        // Temperature Slider
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF161822),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Температура генерации (Temperature)', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.cyanAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(_temperature.toStringAsFixed(2), style: GoogleFonts.jetBrainsMono(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.cyanAccent)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(tempDesc, style: TextStyle(fontSize: 11, color: _temperature < 0.4 ? Colors.cyanAccent : (_temperature <= 0.8 ? Colors.greenAccent : Colors.purpleAccent))),
              Slider(
                value: _temperature,
                min: 0.0,
                max: 2.0,
                divisions: 40,
                activeColor: Colors.cyanAccent,
                inactiveColor: Colors.white10,
                onChanged: (val) {
                  setState(() => _temperature = val);
                  aiSvc.setTemperature(val);
                },
              ),
              const Divider(color: Colors.white10, height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Креативность выборки (Top-P):', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.purpleAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(_topP.toStringAsFixed(2), style: GoogleFonts.jetBrainsMono(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.purpleAccent)),
                  ),
                ],
              ),
              Slider(
                value: _topP,
                min: 0.1,
                max: 1.0,
                divisions: 18,
                activeColor: Colors.purpleAccent,
                inactiveColor: Colors.white10,
                onChanged: (val) {
                  setState(() => _topP = val);
                  aiSvc.setTopP(val);
                },
              ),
            ],
          ),
        ),

        const SizedBox(height: 10),

        // Max Tokens / Context Size
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF161822),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Длина ответа (Max Output Tokens)', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                  Text('$_maxTokens токенов', style: GoogleFonts.jetBrainsMono(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.purpleAccent)),
                ],
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [2048, 4096, 8192, 16384, 32768, 64000, 128000].map((tokens) {
                    final isSel = _maxTokens == tokens;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(tokens >= 1000 ? '${tokens ~/ 1000}K' : '$tokens', style: TextStyle(fontSize: 11, color: isSel ? Colors.black : Colors.white70)),
                        selected: isSel,
                        selectedColor: Colors.purpleAccent,
                        backgroundColor: Colors.white.withValues(alpha: 0.05),
                        onSelected: (_) {
                          setState(() => _maxTokens = tokens);
                          aiSvc.setMaxTokens(tokens);
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 10),

        // System Prompt
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF161822),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Системная роль / Инструкция (System Prompt)', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 6),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _promptPresetChip('Senior Fullstack', 'Ты — Senior Full-Stack разработчик в Quantum IDE. Пиши чистый, типобезопасный и оптимизированный код.'),
                    _promptPresetChip('Flutter Architect', 'Ты — архитектор Flutter приложений. Фокусируйся на виджетах, Riverpod, чистой архитектуре и адаптивности.'),
                    _promptPresetChip('Security Auditor', 'Ты — специалист по кибербезопасности. Ищи уязвимости, валидируй входные данные и проверяй логику.'),
                    _promptPresetChip('C++ / Rust Ninja', 'Ты — эксперт по системному программированию C++, NDK и Rust. Пиши максимально производительный код.'),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _systemPromptController,
                maxLines: 3,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 12),
                onChanged: (text) => aiSvc.setSystemPrompt(text),
                decoration: InputDecoration(
                  hintText: 'Задайте персональную роль или системные инструкции для ассистента...',
                  hintStyle: GoogleFonts.inter(color: Colors.white30, fontSize: 11),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.04),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.all(10),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Section B: Local Hardware Settings
        _settingsSectionHeader('Аппаратные настройки локальных моделей (ARM / GPU)', LucideIcons.cpu),
        const SizedBox(height: 10),

        // RAM & Mobile Anti-Crash Safety Card
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: (localAiState.availableRamMb > 0 && localAiState.availableRamMb < 1800)
                ? Colors.amber.withValues(alpha: 0.12)
                : const Color(0xFF141A28),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: (localAiState.availableRamMb > 0 && localAiState.availableRamMb < 1800)
                  ? Colors.amber.withValues(alpha: 0.4)
                  : Colors.cyanAccent.withValues(alpha: 0.2),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    LucideIcons.hard_drive,
                    size: 16,
                    color: (localAiState.availableRamMb > 0 && localAiState.availableRamMb < 1800)
                        ? Colors.amberAccent
                        : Colors.cyanAccent,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Оперативная память (RAM)',
                    style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                  ),
                  const Spacer(),
                  if (localAiState.availableRamMb > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black38,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Свободно: ${(localAiState.availableRamMb / 1024).toStringAsFixed(1)} ГБ'
                        '${localAiState.totalRamMb > 0 ? " из ${(localAiState.totalRamMb / 1024).toStringAsFixed(1)} ГБ" : ""}',
                        style: GoogleFonts.jetBrainsMono(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.cyanAccent),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Защита от вылетов: запуск тяжелых моделей на смартфонах без запаса памяти вызывает принудительное закрытие приложения операционной системой (Android OOM Killer). Безопасный режим отключает GPU и балансирует потоки.',
                style: GoogleFonts.inter(fontSize: 11, color: Colors.white60, height: 1.3),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await ref.read(localAiServiceProvider.notifier).applyMobileSafeMode();
                    setState(() {
                      _localThreads = 3;
                      _localGpuLayers = 0;
                      _localUseFlashAttn = true;
                    });
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('🛡️ Безопасный режим включен! Потоки=3, GPU=0 (CPU), Контекст=2048'),
                          backgroundColor: Colors.green,
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                  icon: const Icon(LucideIcons.shield_check, size: 14, color: Colors.lightGreenAccent),
                  label: const Text('Применить безопасный режим (Анти-краш)'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.lightGreenAccent,
                    side: const BorderSide(color: Colors.lightGreenAccent),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF161822),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            children: [
              // Server controls
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Сервер llama-server / Ollama:', style: GoogleFonts.inter(fontSize: 12, color: Colors.white70)),
                  Row(
                    children: [
                      if (!localAiState.isRunning && !localAiState.isStarting)
                        ElevatedButton.icon(
                          onPressed: () => ref.read(localAiServiceProvider.notifier).startServer(),
                          icon: const Icon(LucideIcons.play, size: 12),
                          label: const Text('Запустить'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent, foregroundColor: Colors.black, visualDensity: VisualDensity.compact),
                        )
                      else ...[
                        ElevatedButton.icon(
                          onPressed: () => ref.read(localAiServiceProvider.notifier).restartServer(),
                          icon: const Icon(LucideIcons.rotate_cw, size: 12),
                          label: const Text('Рестарт'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.amberAccent, foregroundColor: Colors.black, visualDensity: VisualDensity.compact),
                        ),
                        const SizedBox(width: 6),
                        ElevatedButton.icon(
                          onPressed: () => ref.read(localAiServiceProvider.notifier).stopServer(),
                          icon: const Icon(LucideIcons.square, size: 12),
                          label: const Text('Стоп'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white, visualDensity: VisualDensity.compact),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              const Divider(color: Colors.white10, height: 16),

              // CPU Threads
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Потоки процессора (CPU Threads):', style: TextStyle(fontSize: 12, color: Colors.white70)),
                  Text('$_localThreads ядер', style: GoogleFonts.jetBrainsMono(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.cyanAccent)),
                ],
              ),
              Slider(
                value: _localThreads.toDouble(),
                min: 1,
                max: 16,
                divisions: 15,
                activeColor: Colors.cyanAccent,
                inactiveColor: Colors.white10,
                onChanged: (val) {
                  setState(() => _localThreads = val.toInt());
                  ref.read(localAiServiceProvider.notifier).updateSettings(threads: val.toInt());
                },
              ),

              // GPU Layers
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Слои ускорения GPU / NPU:', style: TextStyle(fontSize: 12, color: Colors.white70)),
                  Text('$_localGpuLayers слоев', style: GoogleFonts.jetBrainsMono(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.lightGreenAccent)),
                ],
              ),
              Slider(
                value: _localGpuLayers.toDouble(),
                min: 0,
                max: 99,
                divisions: 99,
                activeColor: Colors.lightGreenAccent,
                inactiveColor: Colors.white10,
                onChanged: (val) {
                  setState(() => _localGpuLayers = val.toInt());
                  ref.read(localAiServiceProvider.notifier).updateSettings(gpuLayers: val.toInt());
                },
              ),

              // Flash Attention
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Flash Attention (быстрое внимание)', style: TextStyle(fontSize: 12, color: Colors.white)),
                subtitle: const Text('Снижает расход памяти при длинных промптах', style: TextStyle(fontSize: 10, color: Colors.white38)),
                value: _localUseFlashAttn,
                activeThumbColor: Colors.cyanAccent,
                onChanged: (val) {
                  setState(() => _localUseFlashAttn = val);
                  ref.read(localAiServiceProvider.notifier).updateSettings(useFlashAttn: val);
                },
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Section C: Cloud API Providers & Keys
        _settingsSectionHeader('Облачные провайдеры & API Ключи', LucideIcons.key),
        const SizedBox(height: 10),

        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF161822),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Выберите провайдера для настройки:', style: TextStyle(fontSize: 11, color: Colors.white54)),
              const SizedBox(height: 6),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: AiProviders.all.map((p) {
                    final isSel = _settingsProviderId == p.id;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(p.displayName, style: TextStyle(fontSize: 11, color: isSel ? Colors.black : Colors.white70)),
                        selected: isSel,
                        selectedColor: Colors.cyanAccent,
                        backgroundColor: Colors.white.withValues(alpha: 0.05),
                        onSelected: (_) {
                          setState(() {
                            _settingsProviderId = p.id;
                            _apiKeyController.text = aiSvc.getApiKey(p.id);
                            _baseUrlController.text = aiSvc.getBaseUrl(p.id);
                          });
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 12),
              Text('API Ключ для ${_settingsProviderId.toUpperCase()}:', style: const TextStyle(fontSize: 11, color: Colors.white70)),
              const SizedBox(height: 4),
              TextField(
                controller: _apiKeyController,
                obscureText: true,
                style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 12),
                onChanged: (val) => aiSvc.setApiKey(_settingsProviderId, val),
                decoration: InputDecoration(
                  hintText: 'sk-... или AIza...',
                  hintStyle: GoogleFonts.jetBrainsMono(color: Colors.white24, fontSize: 11),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.04),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              const Text('Custom Base URL (Прокси / Локальный адрес):', style: TextStyle(fontSize: 11, color: Colors.white70)),
              const SizedBox(height: 4),
              TextField(
                controller: _baseUrlController,
                style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 12),
                onChanged: (val) => aiSvc.setBaseUrl(_settingsProviderId, val),
                decoration: InputDecoration(
                  hintText: 'https://api.openai.com/v1 или http://127.0.0.1:11434',
                  hintStyle: GoogleFonts.jetBrainsMono(color: Colors.white24, fontSize: 11),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.04),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 30),
      ],
    );
  }

  Widget _promptPresetChip(String title, String prompt) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ActionChip(
        label: Text(title, style: const TextStyle(fontSize: 10, color: Colors.cyanAccent)),
        backgroundColor: Colors.cyanAccent.withValues(alpha: 0.08),
        onPressed: () {
          _systemPromptController.text = prompt;
          ref.read(aiServiceProvider).setSystemPrompt(prompt);
        },
      ),
    );
  }

  Widget _settingsSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.cyanAccent),
        const SizedBox(width: 6),
        Text(title, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
      ],
    );
  }

  // ─── 8. Server Terminal Logs View ────────────────────────────────────────
  Widget _buildLogsView(BuildContext context, LocalAiState localAiState) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: localAiState.isRunning ? Colors.greenAccent : (localAiState.isStarting ? Colors.amberAccent : Colors.redAccent),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    localAiState.isRunning
                        ? 'Сервер активен (127.0.0.1:8080)'
                        : (localAiState.isStarting ? 'Загрузка в оперативную память...' : 'Сервер остановлен'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: localAiState.isRunning ? Colors.greenAccent : (localAiState.isStarting ? Colors.amberAccent : Colors.white60),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(LucideIcons.refresh_cw, size: 14, color: Colors.cyanAccent),
                    tooltip: 'Проверить статус',
                    onPressed: () => ref.read(localAiServiceProvider.notifier).checkStatus(),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.trash_2, size: 14, color: Colors.white54),
                    tooltip: 'Очистить логи',
                    onPressed: () => ref.read(localAiServiceProvider.notifier).clearLogs(),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(color: Colors.white10, height: 1),
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white10),
            ),
            child: localAiState.logs.isEmpty
                ? const Center(child: Text('Логи сервера пусты. Запустите модель для вывода.', style: TextStyle(color: Colors.white24, fontSize: 11)))
                : SingleChildScrollView(
                    reverse: true,
                    child: Text(
                      localAiState.logs,
                      style: GoogleFonts.jetBrainsMono(fontSize: 10.5, color: Colors.greenAccent.withValues(alpha: 0.9)),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
