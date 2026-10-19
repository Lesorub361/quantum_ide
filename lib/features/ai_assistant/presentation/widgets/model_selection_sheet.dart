import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:quantum_ide/core/models/ai_provider_config.dart';
import 'package:quantum_ide/core/models/local_model_metadata.dart';
import 'package:quantum_ide/core/services/ai_service.dart';
import 'package:quantum_ide/core/services/local_ai_service.dart';
import 'package:quantum_ide/core/services/model_catalog_service.dart';
import 'package:quantum_ide/core/services/hugging_face_hub_service.dart';
import 'package:url_launcher/url_launcher.dart';

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
  late int _localContextSize;
  late bool _localSafeMode;
  late String _currentProviderId;

  bool get _isLocalProvider =>
      _currentProviderId == 'local_edge' || _currentProviderId == 'ollama';

  /// Cloud model filter: 'all' | 'free' | 'code' | 'reasoning' | 'claude' | 'gpt' | 'deepseek' | 'qwen'
  String _cloudFilter = 'all';

  /// API key to use for discovery: explicit (non-empty) key from caller,
  /// otherwise the key saved in settings. Empty strings are treated as "no key"
  /// so they never override a saved key.
  String? get _effectiveApiKey {
    final explicit = (widget.apiKey ?? '').trim();
    if (explicit.isNotEmpty && _currentProviderId == widget.providerId) return explicit;
    final typed = _apiKeyController.text.trim();
    if (typed.isNotEmpty) return typed;
    final saved = ref.read(aiServiceProvider).getApiKey(_currentProviderId).trim();
    return saved.isEmpty ? null : saved;
  }

  String? get _effectiveBaseUrl {
    final explicit = (widget.baseUrl ?? '').trim();
    if (explicit.isNotEmpty && _currentProviderId == widget.providerId) return explicit;
    return null;
  }

  void _selectProvider(String pid) {
    if (_currentProviderId == pid) return;
    setState(() {
      _currentProviderId = pid;
      _settingsProviderId = pid;
      final aiSvc = ref.read(aiServiceProvider);
      _apiKeyController.text = aiSvc.getApiKey(pid);
      _baseUrlController.text = aiSvc.getBaseUrl(pid);
      _models = aiSvc.getCachedDiscoveredModels(pid);
      if (_models.isEmpty) {
        _models = AiProviders.getRecommendedDiscoveredModels(pid);
      }
    });
    ref.read(aiServiceProvider).setProvider(pid);
    _discover();
  }

  @override
  void initState() {
    super.initState();
    _currentProviderId = widget.providerId;
    _mainTab = widget.initialMainTab == 1
        ? MainHubTab.settings
        : (widget.initialMainTab == 2 ? MainHubTab.logs : MainHubTab.models);

    final aiSvc = ref.read(aiServiceProvider);
    _models = aiSvc.getCachedDiscoveredModels(_currentProviderId);
    final hasCachedDiscovery = _models.isNotEmpty;
    if (_models.isEmpty) {
      _models = AiProviders.getRecommendedDiscoveredModels(_currentProviderId);
    }

    // Cloud providers (OpenRouter, OpenAI, Groq, ...) must open straight on the
    // cloud model list — not on the local GGUF catalog — and fetch the real
    // model list for the configured API key automatically.
    if (!_isLocalProvider) {
      _localViewMode = LocalViewMode.cloud;
      if (!hasCachedDiscovery) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _discover();
        });
      }
    }

    _settingsProviderId = _currentProviderId;
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
    _localContextSize = localState.contextSize;
    _localSafeMode = localState.safeMode;
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
        _currentProviderId,
        customApiKey: _effectiveApiKey,
        customBaseUrl: _effectiveBaseUrl,
      );

      if (!mounted) return;
      setState(() {
        _models = models;
        _isDiscovering = false;
        _statusMessage = models.isEmpty
            ? 'Список моделей пуст — проверьте API ключ или введите ID модели вручную в поиске'
            : 'Обнаружено ${models.length} моделей';
        _statusOk = models.isNotEmpty;
      });
    } catch (e) {
      if (!mounted) return;
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
    final activeProviderConfig = AiProviders.byId(_currentProviderId);
    final cloudTabLabel = _isLocalProvider ? '☁️ Облачные' : '☁️ ${activeProviderConfig.displayName}';

    return Column(
      children: [
        // Mode Selector Tabs
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _isLocalProvider
                  ? [
                      _subTabButton(LocalViewMode.catalog, '🔥 Топ каталог', LucideIcons.sparkles),
                      const SizedBox(width: 6),
                      _subTabButton(LocalViewMode.downloaded, '💾 Скачанные', LucideIcons.hard_drive),
                      const SizedBox(width: 6),
                      _subTabButton(LocalViewMode.huggingFaceOnline, '🌐 Hugging Face Hub', LucideIcons.globe),
                      const SizedBox(width: 6),
                      _subTabButton(LocalViewMode.ollamaLibrary, '🦙 Ollama Library', LucideIcons.terminal),
                      const SizedBox(width: 6),
                      _subTabButton(LocalViewMode.cloud, cloudTabLabel, LucideIcons.cloud),
                    ]
                  : [
                      _subTabButton(LocalViewMode.cloud, cloudTabLabel, LucideIcons.cloud),
                      const SizedBox(width: 6),
                      _subTabButton(LocalViewMode.catalog, '🔥 Каталог GGUF', LucideIcons.sparkles),
                      const SizedBox(width: 6),
                      _subTabButton(LocalViewMode.downloaded, '💾 Скачанные', LucideIcons.hard_drive),
                      const SizedBox(width: 6),
                      _subTabButton(LocalViewMode.huggingFaceOnline, '🌐 Hugging Face', LucideIcons.globe),
                      const SizedBox(width: 6),
                      _subTabButton(LocalViewMode.ollamaLibrary, '🦙 Ollama', LucideIcons.terminal),
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
        final isDownloaded = model.isOllama
            ? (localAiState.downloadedModels[model.id] == true || localAiState.downloadedModels[model.filename] == true)
            : (catalogState.downloadedModels[model.filename] == true || localAiState.downloadedModels[model.filename] == true);
        final isSelected = activeFilename == model.filename;
        final downloadInfo = catalogState.downloads[model.filename];
        final isOllamaDownloading = localAiState.downloadingModelId == model.id;
        final isDownloading = (downloadInfo != null && downloadInfo.status == DownloadStatus.downloading) || isOllamaDownloading;

        return _buildCatalogCard(
          context,
          model,
          isDownloaded,
          isSelected,
          isDownloading,
          downloadInfo,
          isOllamaDownloading: isOllamaDownloading,
          ollamaProgress: localAiState.downloadProgress,
        );
      },
    );
  }

  Widget _buildCatalogCard(
    BuildContext context,
    LocalModelMetadata model,
    bool isDownloaded,
    bool isSelected,
    bool isDownloading,
    ModelDownloadInfo? downloadInfo, {
    bool isOllamaDownloading = false,
    double ollamaProgress = 0.0,
  }) {
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

          if (isDownloading) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: isOllamaDownloading
                  ? (ollamaProgress > 0 ? ollamaProgress : null)
                  : (downloadInfo?.progress != null && downloadInfo!.progress > 0 ? downloadInfo.progress : null),
              backgroundColor: Colors.white10,
              color: Colors.cyanAccent,
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isOllamaDownloading
                      ? '${(ollamaProgress * 100).toStringAsFixed(1)}% (Загрузка через Ollama...)'
                      : (downloadInfo != null
                          ? '${(downloadInfo.progress * 100).toStringAsFixed(1)}% (${ModelCatalogNotifier.formatBytes(downloadInfo.downloadedBytes)} / ${ModelCatalogNotifier.formatBytes(downloadInfo.totalBytes)})'
                          : 'Загрузка...'),
                  style: const TextStyle(fontSize: 10, color: Colors.white60),
                ),
                if (!isOllamaDownloading && downloadInfo != null)
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
                    if (model.isOllama) {
                      ref.read(localAiServiceProvider.notifier).cancelDownload();
                    } else {
                      ref.read(modelCatalogProvider.notifier).cancelDownload(model.filename);
                    }
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
                    if (model.isOllama) {
                      ref.read(localAiServiceProvider.notifier).downloadModel(model.id);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Загрузка ${model.name} из Ollama начата...')),
                      );
                    } else {
                      final catModel = AiCatalogModel(
                        id: model.id,
                        name: model.name,
                        filename: model.filename,
                        url: model.url,
                        size: model.sizeFormatted,
                        description: model.capabilities,
                        category: model.isVision ? ModelCategory.vision : ModelCategory.text,
                        runtime: ModelRuntime.llama,
                      );
                      ref.read(modelCatalogProvider.notifier).downloadModel(catModel);
                    }
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

  bool _isHfVision(HfModelItem item) {
    final lowerName = item.name.toLowerCase();
    final lowerId = item.id.toLowerCase();
    final pipe = item.pipelineTag?.toLowerCase() ?? '';
    if (pipe.contains('image') || pipe.contains('visual') || pipe.contains('vision')) return true;
    if (lowerName.contains('vl') || lowerName.contains('vision') || lowerName.contains('minicpm-v') || lowerName.contains('llava')) return true;
    if (lowerId.contains('vl') || lowerId.contains('vision') || lowerId.contains('minicpm-v') || lowerId.contains('llava')) return true;
    return item.tags.any((t) => t.contains('vision') || t.contains('image-text-to-text') || t.contains('multimodal'));
  }

  String _extractContextWindow(HfModelItem item) {
    final full = '${item.name} ${item.id} ${item.tags.join(' ')}'.toLowerCase();
    final match = RegExp(r'(\d+)\s*k(?:-context)?').firstMatch(full);
    if (match != null) {
      return '${match.group(1)}K';
    }
    if (full.contains('128k')) return '128K';
    if (full.contains('64k')) return '64K';
    if (full.contains('32k')) return '32K';
    if (full.contains('16k')) return '16K';
    if (full.contains('8k')) return '8K';
    if (full.contains('4k')) return '4K';
    if (full.contains('qwen2.5') || full.contains('qwen-2.5')) return '128K';
    if (full.contains('llama-3.2') || full.contains('llama-3.1')) return '128K';
    if (full.contains('gemma-2')) return '8K';
    if (full.contains('deepseek-r1') || full.contains('deepseek')) return '64K';
    if (full.contains('phi-4') || full.contains('phi-3.5')) return '128K';
    return '32K (Авто)';
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
                              Padding(
                                padding: const EdgeInsets.only(left: 14, right: 14, bottom: 8),
                                child: Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: [
                                    if (_isHfVision(item))
                                      _infoBadge(LucideIcons.eye, 'Зрение (Vision)', Colors.purpleAccent),
                                    _infoBadge(LucideIcons.file_text, 'Контекст: ${_extractContextWindow(item)}', Colors.cyanAccent),
                                    if (item.tags.any((t) => t.contains('code') || t.contains('programming')) || item.name.toLowerCase().contains('coder'))
                                      _infoBadge(LucideIcons.code, 'Код / Programming', Colors.greenAccent),
                                    if (item.tags.any((t) => t.contains('reasoning') || t.contains('r1')) || item.name.toLowerCase().contains('r1'))
                                      _infoBadge(LucideIcons.brain, 'Рассуждения (R1)', Colors.amberAccent),
                                  ],
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
    final localAiState = ref.watch(localAiServiceProvider);
    final availableRam = localAiState.availableRamMb > 0 ? (localAiState.availableRamMb / 1024) : 2.5;

    final popularOllama = [
      {
        'tag': 'qwen2.5:0.5b',
        'name': 'Qwen 2.5 0.5B',
        'desc': 'Ультра-быстрая компактная модель для любых смартфонов',
        'size': '398 MB',
        'ramGb': 0.8,
        'context': '128K',
        'speed': '~35 т/с',
        'isCode': false,
        'isVision': false,
        'isReasoning': false,
      },
      {
        'tag': 'qwen2.5-coder:1.5b',
        'name': 'Qwen 2.5 Coder 1.5B',
        'desc': 'Лучшая модель для анализа кода, скриптов и Pair Programming',
        'size': '986 MB',
        'ramGb': 1.4,
        'context': '128K',
        'speed': '~24 т/с',
        'isCode': true,
        'isVision': false,
        'isReasoning': false,
      },
      {
        'tag': 'llama3.2:1b',
        'name': 'Meta Llama 3.2 1B',
        'desc': 'Современный легкий многоязычный ассистент от Meta',
        'size': '1.3 GB',
        'ramGb': 1.5,
        'context': '128K',
        'speed': '~25 т/с',
        'isCode': false,
        'isVision': false,
        'isReasoning': false,
      },
      {
        'tag': 'deepseek-r1:1.5b',
        'name': 'DeepSeek R1 1.5B',
        'desc': 'Мобильная модель пошагового логического рассуждения (CoT)',
        'size': '1.1 GB',
        'ramGb': 1.6,
        'context': '64K',
        'speed': '~20 т/с',
        'isCode': false,
        'isVision': false,
        'isReasoning': true,
      },
      {
        'tag': 'llama3.2:3b',
        'name': 'Meta Llama 3.2 3B',
        'desc': 'Мощный сбалансированный ИИ ассистент с глубоким пониманием',
        'size': '2.0 GB',
        'ramGb': 2.5,
        'context': '128K',
        'speed': '~14 т/с',
        'isCode': false,
        'isVision': false,
        'isReasoning': false,
      },
      {
        'tag': 'minicpm-v:8b',
        'name': 'MiniCPM-V 2.6 8B',
        'desc': 'Мультимодальная модель: зрение, распознавание фото и диаграмм',
        'size': '5.5 GB',
        'ramGb': 8.5,
        'context': '32K',
        'speed': '~6 т/с',
        'isCode': false,
        'isVision': true,
        'isReasoning': false,
      },
      {
        'tag': 'deepseek-r1:7b',
        'name': 'DeepSeek R1 7B',
        'desc': 'SOTA открытая логическая модель (для мощных устройств/ПК)',
        'size': '4.7 GB',
        'ramGb': 6.8,
        'context': '64K',
        'speed': '~7 т/с',
        'isCode': false,
        'isVision': false,
        'isReasoning': true,
      },
      {
        'tag': 'phi4:14b',
        'name': 'Microsoft Phi-4 14B',
        'desc': 'Флагманский уровень рассуждений и кодинга 2025/2026',
        'size': '9.1 GB',
        'ramGb': 12.0,
        'context': '128K',
        'speed': '~4 т/с',
        'isCode': true,
        'isVision': false,
        'isReasoning': true,
      },
      {
        'tag': 'mistral-nemo:12b',
        'name': 'Mistral NeMo 12B',
        'desc': '128K контекстное окно от Mistral AI для огромных проектов',
        'size': '7.1 GB',
        'ramGb': 10.0,
        'context': '128K',
        'speed': '~5 т/с',
        'isCode': false,
        'isVision': false,
        'isReasoning': false,
      },
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListView(
        children: [
          Text(
            'Загрузка любой модели из Ollama Library:',
            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 4),
          const Text(
            'Введите любой тег с ollama.com или выберите готовую модель из каталога ниже:',
            style: TextStyle(fontSize: 11, color: Colors.white60),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ollamaPullController,
                  style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'phi4:14b или qwen2.5:0.5b',
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
                  await ref.read(localAiServiceProvider.notifier).downloadModel('ollama_$tag');
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Каталог моделей Ollama 2026:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70)),
              Text('Доступно RAM: ${availableRam.toStringAsFixed(1)} ГБ', style: GoogleFonts.jetBrainsMono(fontSize: 10, color: Colors.cyanAccent)),
            ],
          ),
          const SizedBox(height: 8),
          ...popularOllama.map((item) {
            final tag = item['tag'] as String;
            final isDownloadingThis = localAiState.downloadingModelId == 'ollama_$tag' ||
                                      localAiState.downloadingModelId == tag;
            final isDownloaded = (localAiState.downloadedModels[tag] == true) ||
                                 (localAiState.downloadedModels['ollama_$tag'] == true) ||
                                 (localAiState.downloadedModels['$tag:latest'] == true);
            final ramGb = item['ramGb'] as double;
            final isHighRam = ramGb > availableRam;

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF161822),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDownloadingThis
                      ? Colors.cyanAccent.withValues(alpha: 0.6)
                      : isDownloaded
                          ? Colors.greenAccent.withValues(alpha: 0.4)
                          : Colors.white10,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      item['name'] as String,
                                      style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '(${item['tag']})',
                                    style: GoogleFonts.jetBrainsMono(fontSize: 10, color: Colors.white38),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                item['desc'] as String,
                                style: const TextStyle(fontSize: 11, color: Colors.white60, height: 1.25),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (isDownloadingThis)
                          IconButton(
                            icon: const Icon(LucideIcons.x, size: 16, color: Colors.redAccent),
                            tooltip: 'Отменить загрузку',
                            onPressed: () => ref.read(localAiServiceProvider.notifier).cancelDownload(),
                          )
                        else if (isDownloaded)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.greenAccent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.4)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(LucideIcons.check, size: 12, color: Colors.greenAccent),
                                SizedBox(width: 4),
                                Text('Установлена', style: TextStyle(fontSize: 10, color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          )
                        else
                          ElevatedButton.icon(
                            onPressed: () async {
                              _ollamaPullController.text = tag;
                              await ref.read(localAiServiceProvider.notifier).downloadModel('ollama_$tag');
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Загрузка модели $tag через Ollama запущена!')),
                              );
                            },
                            icon: const Icon(LucideIcons.download, size: 12),
                            label: const Text('Скачать', style: TextStyle(fontSize: 11)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.cyanAccent,
                              foregroundColor: Colors.black,
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            ),
                          ),
                      ],
                    ),

                    if (isDownloadingThis) ...[
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: localAiState.downloadProgress > 0 ? localAiState.downloadProgress : null,
                        color: Colors.cyanAccent,
                        backgroundColor: Colors.white12,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Загрузка через Ollama API: ${(localAiState.downloadProgress * 100).toInt()}%',
                        style: GoogleFonts.jetBrainsMono(fontSize: 10, color: Colors.cyanAccent),
                      ),
                    ],

                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (item['isVision'] == true)
                          _infoBadge(LucideIcons.eye, 'Зрение (Vision)', Colors.purpleAccent),
                        if (item['isReasoning'] == true)
                          _infoBadge(LucideIcons.brain, 'Рассуждения (R1)', Colors.amberAccent),
                        if (item['isCode'] == true)
                          _infoBadge(LucideIcons.code, 'Код / Code', Colors.greenAccent),
                        _infoBadge(LucideIcons.file_text, 'Контекст: ${item['context']}', Colors.cyanAccent),
                        _infoBadge(LucideIcons.zap, item['speed'] as String, Colors.orangeAccent),
                        _infoBadge(LucideIcons.hard_drive, '~${item['ramGb']} ГБ RAM', isHighRam ? Colors.redAccent : Colors.lightGreenAccent),
                        _infoBadge(LucideIcons.database, item['size'] as String, Colors.white60),
                        if (isHighRam)
                          _infoBadge(LucideIcons.triangle_alert, 'Мало RAM', Colors.redAccent),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  void _selectAndReturn(String modelId) async {
    final aiSvc = ref.read(aiServiceProvider);
    await aiSvc.setProvider(_currentProviderId);
    await aiSvc.setModel(modelId);
    if (!mounted) return;
    Navigator.pop(context, modelId);
  }

  // ─── 6. Cloud Models List ────────────────────────────────────────────────
  Widget _buildCloudModelsList(BuildContext context, String query) {
    final aiSvc = ref.read(aiServiceProvider);
    final savedKey = aiSvc.getApiKey(_currentProviderId).trim();
    final hasKey = savedKey.isNotEmpty;

    // Apply query and category filter
    final filteredModels = _models.where((m) {
      final mid = m.id.toLowerCase();
      final mname = m.displayName.toLowerCase();
      if (query.isNotEmpty && !mid.contains(query) && !mname.contains(query)) {
        return false;
      }
      switch (_cloudFilter) {
        case 'free':
          return m.isFree || mid.endsWith(':free');
        case 'code':
          return mid.contains('coder') ||
              mid.contains('code') ||
              mname.contains('coder') ||
              mname.contains('code');
        case 'reasoning':
          return mid.contains('r1') ||
              mid.contains('reasoning') ||
              mid.contains('think') ||
              mid.contains('o1') ||
              mid.contains('o3');
        case 'claude':
          return mid.contains('claude') || mname.contains('claude');
        case 'gpt':
          return mid.contains('gpt') || mid.contains('openai') || mname.contains('gpt');
        case 'deepseek':
          return mid.contains('deepseek') || mname.contains('deepseek');
        case 'qwen':
          return mid.contains('qwen') || mname.contains('qwen');
        default:
          return true;
      }
    }).toList();

    final hasExactMatch = query.isEmpty ||
        _models.any((m) => m.id.toLowerCase() == query.toLowerCase());

    final cloudProviders = [
      AiProviders.openrouter,
      AiProviders.deepseek,
      AiProviders.google,
      AiProviders.anthropic,
      AiProviders.openai,
      AiProviders.groq,
      AiProviders.mistral,
      AiProviders.together,
    ];

    return Column(
      children: [
        // 1. Provider Switcher Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: cloudProviders.map((p) {
              final isSelected = p.id == _currentProviderId;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text('${p.logoEmoji} ${p.displayName}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        color: isSelected ? Colors.black : Colors.white70,
                      )),
                  selected: isSelected,
                  selectedColor: Colors.cyanAccent,
                  backgroundColor: Colors.white.withValues(alpha: 0.06),
                  onSelected: (_) => _selectProvider(p.id),
                ),
              );
            }).toList(),
          ),
        ),

        // 2. API Key Box / Status Bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: hasKey
                  ? Colors.greenAccent.withValues(alpha: 0.06)
                  : Colors.amberAccent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: hasKey
                    ? Colors.greenAccent.withValues(alpha: 0.25)
                    : Colors.amberAccent.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      hasKey ? LucideIcons.key_round : LucideIcons.shield_alert,
                      size: 13,
                      color: hasKey ? Colors.greenAccent : Colors.amberAccent,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        hasKey
                            ? 'API Ключ ${_currentProviderId.toUpperCase()}: ${savedKey.length > 8 ? "${savedKey.substring(0, 6)}••••${savedKey.substring(savedKey.length - 3)}" : "Задан"}'
                            : 'API Ключ для ${_currentProviderId.toUpperCase()} не задан',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: hasKey ? Colors.greenAccent : Colors.amberAccent,
                        ),
                      ),
                    ),
                    if (_currentProviderId == 'openrouter')
                      TextButton(
                        onPressed: () async {
                          final uri = Uri.parse('https://openrouter.ai/keys');
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                          }
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Получить ключ ↗',
                            style: TextStyle(fontSize: 10, color: Colors.cyanAccent)),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 32,
                        child: TextField(
                          controller: _apiKeyController,
                          obscureText: true,
                          style: GoogleFonts.jetBrainsMono(fontSize: 11, color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'Вставьте API ключ сюда...',
                            hintStyle: const TextStyle(fontSize: 11, color: Colors.white38),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            filled: true,
                            fillColor: Colors.black26,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                            ),
                            isDense: true,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () async {
                        final key = _apiKeyController.text.trim();
                        final messenger = ScaffoldMessenger.of(context);
                        await ref.read(aiServiceProvider).setApiKey(_currentProviderId, key);
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text('Ключ для ${_currentProviderId.toUpperCase()} сохранён'),
                            duration: const Duration(seconds: 1),
                          ),
                        );
                        _discover();
                      },
                      icon: const Icon(LucideIcons.check, size: 12),
                      label: const Text('Сохранить', style: TextStyle(fontSize: 11)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.cyanAccent,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        // 3. Quick Cloud Filter Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
          child: Row(
            children: [
              {'id': 'all', 'label': 'Все модели'},
              {'id': 'free', 'label': '🆓 Бесплатные (:free)'},
              {'id': 'code', 'label': '💻 Для кода'},
              {'id': 'reasoning', 'label': '🧠 Рассуждения (R1)'},
              {'id': 'claude', 'label': 'Claude'},
              {'id': 'gpt', 'label': 'GPT-4o / o3'},
              {'id': 'deepseek', 'label': 'DeepSeek'},
              {'id': 'qwen', 'label': 'Qwen 2.5'},
            ].map((f) {
              final isSel = _cloudFilter == f['id'];
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(f['label']!,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
                        color: isSel ? Colors.black : Colors.white70,
                      )),
                  selected: isSel,
                  selectedColor: Colors.purpleAccent,
                  backgroundColor: Colors.white.withValues(alpha: 0.05),
                  onSelected: (_) => setState(() => _cloudFilter = f['id']!),
                ),
              );
            }).toList(),
          ),
        ),

        // 4. Status Bar & Refresh
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Доступно моделей: ${filteredModels.length}',
                style: const TextStyle(fontSize: 11, color: Colors.white54, fontWeight: FontWeight.bold),
              ),
              TextButton.icon(
                onPressed: _isDiscovering ? null : _discover,
                icon: _isDiscovering
                    ? const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.cyanAccent))
                    : const Icon(LucideIcons.refresh_cw, size: 11, color: Colors.cyanAccent),
                label: Text(_isDiscovering ? 'Загрузка...' : 'Обновить по ключу',
                    style: const TextStyle(fontSize: 10, color: Colors.cyanAccent)),
              ),
            ],
          ),
        ),

        // 5. Models List
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            itemCount: filteredModels.length + (!hasExactMatch && query.isNotEmpty ? 1 : 0),
            separatorBuilder: (_, _) => const SizedBox(height: 6),
            itemBuilder: (context, index) {
              // Custom model tile if user types custom query
              if (!hasExactMatch && query.isNotEmpty && index == 0) {
                return Container(
                  decoration: BoxDecoration(
                    color: Colors.cyanAccent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.cyanAccent, width: 1.5),
                  ),
                  child: ListTile(
                    dense: true,
                    leading: const Icon(LucideIcons.sparkles, color: Colors.cyanAccent, size: 20),
                    title: Text(
                      'Использовать модель: "$query"',
                      style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.cyanAccent),
                    ),
                    subtitle: Text(
                      'Нажмите для подключения любого ID модели из OpenRouter / API',
                      style: GoogleFonts.inter(fontSize: 11, color: Colors.white70),
                    ),
                    trailing: const Icon(LucideIcons.arrow_right, color: Colors.cyanAccent, size: 16),
                    onTap: () => _selectAndReturn(query),
                  ),
                );
              }

              final realIndex = !hasExactMatch && query.isNotEmpty ? index - 1 : index;
              final model = filteredModels[realIndex];
              final isSelected = model.id == widget.currentModel;
              final isFree = model.isFree || model.id.endsWith(':free');
              final isCode = model.id.toLowerCase().contains('code') || model.displayName.toLowerCase().contains('code');
              final isReasoning = model.id.toLowerCase().contains('r1') || model.id.toLowerCase().contains('think') || model.id.toLowerCase().contains('reasoning');

              return Container(
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF1E2838) : const Color(0xFF161822),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected ? Colors.cyanAccent : Colors.white10,
                    width: isSelected ? 1.5 : 1.0,
                  ),
                ),
                child: ListTile(
                  dense: true,
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          model.displayName,
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: isSelected ? Colors.cyanAccent : Colors.white,
                          ),
                        ),
                      ),
                      if (isFree)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          margin: const EdgeInsets.only(left: 4),
                          decoration: BoxDecoration(
                            color: Colors.greenAccent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.4)),
                          ),
                          child: const Text('FREE',
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.greenAccent)),
                        ),
                      if (isCode)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          margin: const EdgeInsets.only(left: 4),
                          decoration: BoxDecoration(
                            color: Colors.cyanAccent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('CODE',
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.cyanAccent)),
                        ),
                      if (isReasoning)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          margin: const EdgeInsets.only(left: 4),
                          decoration: BoxDecoration(
                            color: Colors.purpleAccent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('THINK',
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.purpleAccent)),
                        ),
                    ],
                  ),
                  subtitle: Text(
                    model.id,
                    style: GoogleFonts.jetBrainsMono(fontSize: 10.5, color: Colors.white54),
                  ),
                  trailing: isSelected
                      ? const Icon(LucideIcons.circle_check, size: 18, color: Colors.cyanAccent)
                      : const Icon(LucideIcons.chevron_right, size: 16, color: Colors.white24),
                  onTap: () => _selectAndReturn(model.id),
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
                          setState(() {
                            _maxTokens = tokens;
                            _localContextSize = tokens;
                          });
                          aiSvc.setMaxTokens(tokens);
                          ref.read(localAiServiceProvider.notifier).updateSettings(contextSize: tokens);
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
                        '${localAiState.totalRamMb > 0 ? " (RAM: ${(localAiState.totalRamMb / 1024).toStringAsFixed(1)} ГБ)" : ""}',
                        style: GoogleFonts.jetBrainsMono(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.cyanAccent),
                      ),
                    ),
                ],
              ),
              if (localAiState.swapTotalMb > 0) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.purple.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.purpleAccent.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.hard_drive_download, size: 12, color: Colors.purpleAccent),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Подкачка Android (RAM Plus): +${(localAiState.swapTotalMb / 1024).toStringAsFixed(1)} ГБ (свободно ${(localAiState.swapFreeMb / 1024).toStringAsFixed(1)} ГБ) · Всего пула: ${((localAiState.totalRamMb + localAiState.swapTotalMb) / 1024).toStringAsFixed(1)} ГБ',
                          style: GoogleFonts.jetBrainsMono(fontSize: 10, color: Colors.purpleAccent, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                '💡 Доступная память для ИИ: из ${localAiState.totalRamMb > 0 ? (localAiState.totalRamMb / 1024).toStringAsFixed(1) : "8.0"} ГБ физической RAM система Android резервирует часть под экран и модем (поэтому отображается ${(localAiState.totalRamMb / 1024).toStringAsFixed(1)} ГБ).'
                '${localAiState.swapTotalMb > 0 ? " Дополнительно активен файл подкачки на ${(localAiState.swapTotalMb / 1024).toStringAsFixed(1)} ГБ (итого: ${((localAiState.totalRamMb + localAiState.swapTotalMb) / 1024).toStringAsFixed(1)} ГБ)." : ""}'
                ' Чистый свободный остаток физической RAM — ${(localAiState.availableRamMb / 1024).toStringAsFixed(1)} ГБ.',
                style: GoogleFonts.inter(fontSize: 11, color: Colors.white70, height: 1.3),
              ),
              const SizedBox(height: 6),
              Text(
                'Защита от вылетов: запуск тяжелых моделей на смартфонах без запаса памяти вызывает принудительное закрытие приложения операционной системой (Android OOM Killer). Безопасный режим отключает GPU и балансирует потоки.',
                style: GoogleFonts.inter(fontSize: 10, color: Colors.white54, height: 1.25),
              ),
              const SizedBox(height: 8),

              // Safe Mode Toggle Switch
              Container(
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _localSafeMode ? Colors.lightGreenAccent.withValues(alpha: 0.3) : Colors.orangeAccent.withValues(alpha: 0.3),
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                child: SwitchListTile(
                  value: _localSafeMode,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: Colors.lightGreenAccent,
                  inactiveThumbColor: Colors.orangeAccent,
                  title: Row(
                    children: [
                      Icon(
                        _localSafeMode ? LucideIcons.shield_check : LucideIcons.shield_alert,
                        size: 15,
                        color: _localSafeMode ? Colors.lightGreenAccent : Colors.orangeAccent,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Безопасный режим (Safe Mode)',
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                  subtitle: Text(
                    _localSafeMode
                        ? 'ВКЛЮЧЕН: блокирует запуск при нехватке RAM для защиты от вылетов.'
                        : 'ОТКЛЮЧЕН: ограничения сняты. Запуск любых моделей на ваш страх и риск.',
                    style: TextStyle(
                      fontSize: 10,
                      color: _localSafeMode ? Colors.white60 : Colors.orangeAccent,
                    ),
                  ),
                  onChanged: (val) async {
                    setState(() => _localSafeMode = val);
                    await ref.read(localAiServiceProvider.notifier).setSafeMode(val);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(val
                              ? '🛡️ Безопасный режим ВКЛЮЧЕН: защита от вылетов активна'
                              : '⚠️ Безопасный режим ОТКЛЮЧЕН: все ограничения сняты'),
                          backgroundColor: val ? Colors.green : Colors.deepOrange,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                ),
              ),
              const SizedBox(height: 8),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await ref.read(localAiServiceProvider.notifier).applyMobileSafeMode();
                    setState(() {
                      _localThreads = 3;
                      _localGpuLayers = 0;
                      _localUseFlashAttn = true;
                      _localContextSize = 2048;
                      _localSafeMode = true;
                    });
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('🛡️ Настройки сброшены к безопасным: Потоки=3, GPU=0 (CPU), Контекст=2048'),
                          backgroundColor: Colors.green,
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                  icon: const Icon(LucideIcons.rotate_ccw, size: 13, color: Colors.lightGreenAccent),
                  label: const Text('Сбросить к безопасным настройкам'),
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

              // Model Context Size (-c)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Контекст модели (-c Context Size):', style: TextStyle(fontSize: 12, color: Colors.white70)),
                  Text(
                    '$_localContextSize токенов (${_localContextSize >= 1000 ? "${_localContextSize ~/ 1000}K" : "$_localContextSize"})',
                    style: GoogleFonts.jetBrainsMono(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.purpleAccent),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [512, 1024, 2048, 4096, 8192, 16384, 32768].map((ctx) {
                    final isSel = _localContextSize == ctx;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(ctx >= 1000 ? '${ctx ~/ 1000}K' : '$ctx', style: TextStyle(fontSize: 11, color: isSel ? Colors.black : Colors.white70)),
                        selected: isSel,
                        selectedColor: Colors.purpleAccent,
                        backgroundColor: Colors.white.withValues(alpha: 0.05),
                        onSelected: (_) {
                          setState(() {
                            _localContextSize = ctx;
                            _maxTokens = ctx;
                          });
                          ref.read(localAiServiceProvider.notifier).updateSettings(contextSize: ctx);
                          ref.read(aiServiceProvider).setMaxTokens(ctx);
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 12),

              // CPU Threads
              Builder(
                builder: (context) {
                  final maxCpuCores = Platform.numberOfProcessors > 0 ? Platform.numberOfProcessors : 8;
                  return Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Потоки процессора (CPU Threads):', style: TextStyle(fontSize: 12, color: Colors.white70)),
                          Text(
                            '$_localThreads из $maxCpuCores ядер',
                            style: GoogleFonts.jetBrainsMono(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.cyanAccent),
                          ),
                        ],
                      ),
                      Slider(
                        value: _localThreads.clamp(1, maxCpuCores).toDouble(),
                        min: 1,
                        max: maxCpuCores.toDouble(),
                        divisions: (maxCpuCores - 1) > 0 ? (maxCpuCores - 1) : 1,
                        activeColor: Colors.cyanAccent,
                        inactiveColor: Colors.white10,
                        onChanged: (val) {
                          setState(() => _localThreads = val.toInt());
                          ref.read(localAiServiceProvider.notifier).updateSettings(threads: val.toInt());
                        },
                      ),
                    ],
                  );
                },
              ),

              // GPU Layers
              Builder(
                builder: (context) {
                  final maxGpuLayers = _localSafeMode ? 33 : 99;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Слои ускорения GPU / NPU${!_localSafeMode ? " (до 99)" : ""}:', style: const TextStyle(fontSize: 12, color: Colors.white70)),
                          Text(
                            '$_localGpuLayers ${_localGpuLayers == 0 ? "(Чистый CPU)" : "слоев"}',
                            style: GoogleFonts.jetBrainsMono(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.lightGreenAccent),
                          ),
                        ],
                      ),
                      Slider(
                        value: _localGpuLayers.clamp(0, maxGpuLayers).toDouble(),
                        min: 0,
                        max: maxGpuLayers.toDouble(),
                        divisions: maxGpuLayers,
                        activeColor: Colors.lightGreenAccent,
                        inactiveColor: Colors.white10,
                        onChanged: (val) {
                          setState(() => _localGpuLayers = val.toInt());
                          ref.read(localAiServiceProvider.notifier).updateSettings(gpuLayers: val.toInt());
                        },
                      ),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: (_localSafeMode ? [0, 8, 16, 24, 33] : [0, 8, 16, 33, 48, 64, 99]).map((l) {
                            final isSel = _localGpuLayers == l;
                            return Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ActionChip(
                                label: Text(l == 0 ? '0 (CPU)' : '$l слоев', style: TextStyle(fontSize: 10, color: isSel ? Colors.black : Colors.white70)),
                                backgroundColor: isSel ? Colors.lightGreenAccent : Colors.white.withValues(alpha: 0.05),
                                onPressed: () {
                                  setState(() => _localGpuLayers = l);
                                  ref.read(localAiServiceProvider.notifier).updateSettings(gpuLayers: l);
                                },
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 8),

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
                    icon: const Icon(LucideIcons.copy, size: 14, color: Colors.cyanAccent),
                    tooltip: 'Копировать все логи',
                    onPressed: () {
                      if (localAiState.logs.trim().isNotEmpty) {
                        Clipboard.setData(ClipboardData(text: localAiState.logs));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('📋 Логи скопированы в буфер обмена! Отправьте их для анализа ошибки.'),
                            backgroundColor: Colors.green,
                            duration: Duration(seconds: 3),
                          ),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Логи сервера пока пусты'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                  ),
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
