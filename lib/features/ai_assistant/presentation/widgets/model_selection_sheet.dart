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
import 'local_models_dialog.dart';

enum LocalViewMode { catalog, huggingFaceOnline, ollamaLibrary }

Future<String?> showModelPickerModal(
  BuildContext context, {
  required String providerId,
  required String currentModel,
  String? apiKey,
  String? baseUrl,
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
    ),
  );
}

class ModelSelectionSheet extends ConsumerStatefulWidget {
  final String providerId;
  final String currentModel;
  final String? apiKey;
  final String? baseUrl;

  const ModelSelectionSheet({
    super.key,
    required this.providerId,
    required this.currentModel,
    this.apiKey,
    this.baseUrl,
  });

  @override
  ConsumerState<ModelSelectionSheet> createState() => _ModelSelectionSheetState();
}

class _ModelSelectionSheetState extends ConsumerState<ModelSelectionSheet> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _hfSearchController = TextEditingController();
  final TextEditingController _ollamaPullController = TextEditingController();

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

  bool get _isLocalProvider =>
      widget.providerId == 'local_edge' || widget.providerId == 'ollama';

  @override
  void initState() {
    super.initState();
    final aiSvc = ref.read(aiServiceProvider);
    _models = aiSvc.getCachedDiscoveredModels(widget.providerId);
    if (_models.isEmpty) {
      _models = AiProviders.getRecommendedDiscoveredModels(widget.providerId);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _hfSearchController.dispose();
    _ollamaPullController.dispose();
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
      _statusMessage = 'Поиск доступных моделей...';
      _statusOk = true;
    });

    try {
      final aiSvc = ref.read(aiServiceProvider);
      final discovered = await aiSvc.discoverModels(
        widget.providerId,
        customBaseUrl: widget.baseUrl,
        customApiKey: widget.apiKey,
      );

      setState(() {
        _models = discovered;
        _isDiscovering = false;
        _statusMessage = 'Найдено ${_models.length} моделей от ${AiProviders.byId(widget.providerId).displayName}';
        _statusOk = true;
      });
    } catch (e) {
      setState(() {
        _isDiscovering = false;
        _statusMessage = 'Ошибка при загрузке списка: $e';
        _statusOk = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = AiProviders.byId(widget.providerId);
    final query = _searchController.text.trim().toLowerCase();

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF11141F),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(
          top: BorderSide(color: Colors.white12, width: 1),
          left: BorderSide(color: Colors.white12, width: 1),
          right: BorderSide(color: Colors.white12, width: 1),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Text(
                  provider.logoEmoji,
                  style: const TextStyle(fontSize: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isLocalProvider ? 'Локальные ИИ Модели' : 'Выбор модели ИИ',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        _isLocalProvider
                            ? 'Каталог, поиск в Hugging Face и загрузка из Ollama'
                            : '${provider.displayName} · ${_models.length} моделей',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: Colors.white54,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_isLocalProvider) ...[
                  TextButton.icon(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (_) => const LocalModelsDialog(),
                      );
                    },
                    icon: const Icon(LucideIcons.folder_down, size: 13, color: Colors.cyanAccent),
                    label: Text(
                      'Проводник',
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.cyanAccent),
                    ),
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.cyanAccent.withValues(alpha: 0.12),
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(width: 6),
                ] else ...[
                  // Refresh / Discover button
                  TextButton.icon(
                    onPressed: _isDiscovering ? null : _discover,
                    icon: _isDiscovering
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyanAccent),
                          )
                        : const Icon(LucideIcons.refresh_cw, size: 12, color: Colors.cyanAccent),
                    label: Text(
                      _isDiscovering ? 'Поиск...' : 'API Каталог',
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.cyanAccent),
                    ),
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.cyanAccent.withValues(alpha: 0.12),
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                IconButton(
                  icon: const Icon(LucideIcons.x, size: 18, color: Colors.white54),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ],
            ),
          ),

          // Local Mode Selector Tabs (Каталог / Hugging Face Онлайн / Ollama Library)
          if (_isLocalProvider)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  children: [
                    _tabButton(LocalViewMode.catalog, '🔥 Топ каталог', LucideIcons.sparkles),
                    _tabButton(LocalViewMode.huggingFaceOnline, '🌐 Hugging Face Hub', LucideIcons.globe),
                    _tabButton(LocalViewMode.ollamaLibrary, '🦙 Ollama Library', LucideIcons.terminal),
                  ],
                ),
              ),
            ),

          // Search Box (Dynamic for current mode)
          if (!_isLocalProvider || _localViewMode == LocalViewMode.catalog)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: _isLocalProvider ? 'Поиск модели, параметров или кодинга...' : 'Поиск модели или ввод ID...',
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
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  isDense: true,
                ),
              ),
            ),

          // Category filter pills for Local models (only in catalog mode)
          if (_isLocalProvider && _localViewMode == LocalViewMode.catalog)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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

          // Status message (if any)
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

          const Divider(color: Colors.white10, height: 10),

          // Models List / Sub-views
          Expanded(
            child: _buildCurrentView(context, query),
          ),
        ],
      ),
    );
  }

  Widget _tabButton(LocalViewMode mode, String label, IconData icon) {
    final isSelected = _localViewMode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _localViewMode = mode);
          if (mode == LocalViewMode.huggingFaceOnline && _hfResults.isEmpty) {
            _searchHuggingFace('');
          }
        },
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
                  fontSize: 10.5,
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

  Widget _buildCurrentView(BuildContext context, String query) {
    if (!_isLocalProvider) {
      return _buildCloudModelsList(context, query);
    }

    switch (_localViewMode) {
      case LocalViewMode.catalog:
        return _buildLocalModelsList(context, query);
      case LocalViewMode.huggingFaceOnline:
        return _buildHuggingFaceOnlineView(context);
      case LocalViewMode.ollamaLibrary:
        return _buildOllamaLibraryView(context);
    }
  }

  // ─── 1. Local Models Catalog (Curated SOTA) ───────────────────────────────
  Widget _buildLocalModelsList(BuildContext context, String query) {
    final localAiState = ref.watch(localAiServiceProvider);
    final catalogState = ref.watch(modelCatalogProvider);
    final isOllama = widget.providerId == 'ollama';

    final candidates = LocalModelMetadata.catalog.where((m) {
      if (isOllama && !m.isOllama) return false;
      if (!isOllama && m.isOllama) return false;
      if (_selectedCategory != 'Все' && m.category != _selectedCategory) {
        return false;
      }
      if (query.isNotEmpty) {
        final matchesName = m.name.toLowerCase().contains(query);
        final matchesCap = m.capabilities.toLowerCase().contains(query);
        final matchesId = m.id.toLowerCase().contains(query);
        final matchesCat = m.category.toLowerCase().contains(query);
        return matchesName || matchesCap || matchesId || matchesCat;
      }
      return true;
    }).toList();

    if (candidates.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.bot, size: 36, color: Colors.white24),
              const SizedBox(height: 12),
              Text('Модели не найдены по фильтру', style: GoogleFonts.inter(color: Colors.white54, fontSize: 13)),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: candidates.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = candidates[index];
        return _buildLocalModelCard(context, item, localAiState, catalogState);
      },
    );
  }

  Widget _buildLocalModelCard(
    BuildContext context,
    LocalModelMetadata item,
    LocalAiState localAiState,
    ModelCatalogState catalogState,
  ) {
    bool isDownloaded = false;
    if (item.isOllama) {
      isDownloaded = localAiState.downloadedModels[item.id] == true ||
          localAiState.downloadedModels[item.filename] == true ||
          _models.any((m) => m.id == item.filename || m.id == '${item.filename}:latest');
    } else {
      isDownloaded = catalogState.downloadedModels[item.filename] == true ||
          localAiState.downloadedModels[item.id] == true ||
          localAiState.selectedModelFilename == item.filename;
    }

    final isDownloadingThis = localAiState.downloadingModelId == item.id ||
        localAiState.downloadingModelId == item.filename;
    final downloadProgress = isDownloadingThis ? localAiState.downloadProgress : 0.0;

    final isSelected = widget.currentModel == item.filename ||
        widget.currentModel == item.id ||
        widget.currentModel == '${item.filename}:latest';

    Color categoryColor;
    IconData categoryIcon;
    switch (item.category) {
      case 'Код':
        categoryColor = Colors.cyanAccent;
        categoryIcon = LucideIcons.code;
        break;
      case 'Рассуждения':
        categoryColor = const Color(0xFFA855F7);
        categoryIcon = LucideIcons.brain;
        break;
      case 'Зрение':
        categoryColor = const Color(0xFFF59E0B);
        categoryIcon = LucideIcons.eye;
        break;
      default:
        categoryColor = const Color(0xFF10B981);
        categoryIcon = LucideIcons.message_square;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isSelected
            ? categoryColor.withValues(alpha: 0.12)
            : const Color(0xFF181B26),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected
              ? categoryColor.withValues(alpha: 0.7)
              : Colors.white.withValues(alpha: 0.08),
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(categoryIcon, size: 16, color: categoryColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.name,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: categoryColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  item.category,
                  style: TextStyle(color: categoryColor, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            item.capabilities,
            style: GoogleFonts.inter(fontSize: 11.5, color: Colors.white70),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _paramBadge(LucideIcons.hard_drive, item.sizeFormatted, Colors.blueAccent),
              _paramBadge(LucideIcons.cpu, item.ramRequiredFormatted, Colors.purpleAccent),
              _paramBadge(LucideIcons.file_text, item.contextWindow, Colors.amberAccent),
              _paramBadge(LucideIcons.zap, '${item.speedEstimate} (${item.speedRating})', Colors.greenAccent),
              _paramBadge(LucideIcons.binary, item.quantization, Colors.grey),
            ],
          ),
          const SizedBox(height: 10),
          if (isDownloadingThis) ...[
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: downloadProgress > 0 ? downloadProgress : null,
                          backgroundColor: Colors.white10,
                          valueColor: const AlwaysStoppedAnimation(Colors.cyanAccent),
                          minHeight: 6,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${(downloadProgress * 100).toStringAsFixed(0)}%',
                      style: GoogleFonts.jetBrainsMono(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.cyanAccent),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () => ref.read(localAiServiceProvider.notifier).cancelDownload(),
                      child: const Icon(LucideIcons.x, size: 16, color: Colors.redAccent),
                    ),
                  ],
                ),
              ],
            ),
          ] else ...[
            Row(
              children: [
                if (isDownloaded) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(LucideIcons.check, size: 12, color: Color(0xFF10B981)),
                        const SizedBox(width: 4),
                        Text(
                          'Загружена на устройство',
                          style: GoogleFonts.inter(color: const Color(0xFF10B981), fontSize: 10.5, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: () {
                      final selected = item.filename;
                      Navigator.pop(context, selected);
                    },
                    icon: Icon(isSelected ? LucideIcons.check : LucideIcons.play, size: 12),
                    label: Text(isSelected ? 'Активна' : 'Выбрать модель', style: const TextStyle(fontSize: 11)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isSelected ? Colors.cyanAccent : const Color(0xFF3B82F6),
                      foregroundColor: isSelected ? Colors.black : Colors.white,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    ),
                  ),
                ] else ...[
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: () async {
                      if (item.isOllama) {
                        final modelInfo = availableLocalModels.firstWhere(
                          (m) => m.filename == item.filename || m.id == item.id,
                          orElse: () => LocalModelInfo(
                            id: item.id,
                            name: item.name,
                            description: item.capabilities,
                            filename: item.filename,
                            sizeGb: 1.0,
                            ramRequiredGb: 2.5,
                            url: item.filename,
                            engine: LocalAiEngine.ollama,
                          ),
                        );
                        await ref.read(localAiServiceProvider.notifier).downloadModel(modelInfo.id);
                      } else {
                        final modelInfo = availableLocalModels.firstWhere(
                          (m) => m.filename == item.filename,
                          orElse: () => LocalModelInfo(
                            id: item.id,
                            name: item.name,
                            description: item.capabilities,
                            filename: item.filename,
                            sizeGb: 1.0,
                            ramRequiredGb: 2.5,
                            url: item.url,
                            engine: LocalAiEngine.llamaServer,
                          ),
                        );
                        await ref.read(localAiServiceProvider.notifier).downloadModel(modelInfo.id);
                      }
                    },
                    icon: const Icon(LucideIcons.download, size: 13),
                    label: Text(
                      'Скачать (${item.sizeFormatted})',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.cyanAccent,
                      foregroundColor: Colors.black,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ─── 2. Live Hugging Face Hub Online Search ───────────────────────────────
  Widget _buildHuggingFaceOnlineView(BuildContext context) {
    final catalogState = ref.watch(modelCatalogProvider);

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

        // Quick tags
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
                            color: const Color(0xFF181B26),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ListTile(
                                onTap: () => _loadHfRepoFiles(item.id),
                                dense: true,
                                title: Text(
                                  item.id,
                                  style: GoogleFonts.jetBrainsMono(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.cyanAccent),
                                ),
                                subtitle: Row(
                                  children: [
                                    Text('⬇️ ${_formatCompact(item.downloads)}', style: const TextStyle(fontSize: 11, color: Colors.white60)),
                                    const SizedBox(width: 10),
                                    Text('❤️ ${item.likes}', style: const TextStyle(fontSize: 11, color: Colors.white60)),
                                    const SizedBox(width: 10),
                                    if (item.pipelineTag != null)
                                      Text(item.pipelineTag!, style: const TextStyle(fontSize: 10, color: Colors.purpleAccent)),
                                  ],
                                ),
                                trailing: Icon(
                                  isExpanded ? LucideIcons.chevron_up : LucideIcons.chevron_down,
                                  size: 16,
                                  color: Colors.white54,
                                ),
                              ),
                              if (isExpanded) ...[
                                const Divider(color: Colors.white10, height: 1),
                                if (_isLoadingHfFiles && files == null)
                                  const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: Center(child: CircularProgressIndicator(color: Colors.cyanAccent, strokeWidth: 2)),
                                  )
                                else if (files == null || files.isEmpty)
                                  const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: Text('GGUF файлы не найдены в репозитории', style: TextStyle(color: Colors.white54, fontSize: 11)),
                                  )
                                else
                                  Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text('Доступные квантования GGUF:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white70)),
                                        const SizedBox(height: 6),
                                        ...files.map((file) {
                                          final isDownloaded = catalogState.downloadedModels[file.filename] == true;
                                          return Padding(
                                            padding: const EdgeInsets.symmetric(vertical: 4),
                                            child: Row(
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: Colors.cyanAccent.withValues(alpha: 0.15),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: Text(
                                                    file.quantization,
                                                    style: const TextStyle(color: Colors.cyanAccent, fontSize: 10, fontWeight: FontWeight.bold),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    '${file.filename} (${file.sizeFormatted})',
                                                    style: GoogleFonts.jetBrainsMono(fontSize: 11, color: Colors.white),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                if (isDownloaded)
                                                  ElevatedButton(
                                                    onPressed: () => Navigator.pop(context, file.filename),
                                                    style: ElevatedButton.styleFrom(
                                                      backgroundColor: const Color(0xFF10B981),
                                                      visualDensity: VisualDensity.compact,
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                    ),
                                                    child: const Text('Выбрать', style: TextStyle(fontSize: 10)),
                                                  )
                                                else
                                                  ElevatedButton.icon(
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
                                              ],
                                            ),
                                          );
                                        }),
                                      ],
                                    ),
                                  ),
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

  // ─── 3. Ollama Library Pull View ──────────────────────────────────────────
  Widget _buildOllamaLibraryView(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: [
          Text(
            'Загрузка любой модели из Ollama Library',
            style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 4),
          const Text(
            'Вы можете ввести имя любого тега с официального сайта ollama.com/library (например, phi4:14b, deepseek-r1:14b, llama3.3:70b)',
            style: TextStyle(color: Colors.white60, fontSize: 11),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ollamaPullController,
                  style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Имя модели (например: phi4:14b)...',
                    hintStyle: GoogleFonts.jetBrainsMono(color: Colors.white38, fontSize: 12),
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

  // ─── 4. Cloud Models ──────────────────────────────────────────────────────
  Widget _buildCloudModelsList(BuildContext context, String query) {
    final filteredModels = query.isEmpty
        ? _models
        : _models.where((m) {
            return m.id.toLowerCase().contains(query) ||
                m.displayName.toLowerCase().contains(query);
          }).toList();

    if (filteredModels.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.bot, size: 36, color: Colors.white24),
              const SizedBox(height: 12),
              Text('Модели не найдены по запросу "$query"', style: GoogleFonts.inter(color: Colors.white54, fontSize: 13)),
              if (query.isNotEmpty) ...[
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context, _searchController.text.trim()),
                  icon: const Icon(LucideIcons.sparkles, size: 14),
                  label: Text('Использовать ID: ${_searchController.text.trim()}'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      itemCount: filteredModels.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final item = filteredModels[index];
        final isSelected = item.id == widget.currentModel;

        return InkWell(
          onTap: () => Navigator.pop(context, item.id),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected ? Colors.cyanAccent.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected ? Colors.cyanAccent.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.06),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              item.displayName,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                color: isSelected ? Colors.cyanAccent : Colors.white,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (item.isFree) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                              ),
                              child: Text(
                                'FREE',
                                style: GoogleFonts.inter(color: const Color(0xFF10B981), fontSize: 9, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(item.id, style: GoogleFonts.jetBrainsMono(fontSize: 11, color: Colors.white38)),
                    ],
                  ),
                ),
                if (isSelected)
                  const Icon(Icons.check_circle_rounded, color: Colors.cyanAccent, size: 18),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _paramBadge(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 0.6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  String _formatCompact(int number) {
    if (number >= 1000000) return '${(number / 1000000).toStringAsFixed(1)}M';
    if (number >= 1000) return '${(number / 1000).toStringAsFixed(1)}k';
    return number.toString();
  }
}
