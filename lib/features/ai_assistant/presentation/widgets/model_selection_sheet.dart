import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:quantum_ide/core/models/ai_provider_config.dart';
import 'package:quantum_ide/core/models/local_model_metadata.dart';
import 'package:quantum_ide/core/services/ai_service.dart';
import 'package:quantum_ide/core/services/local_ai_service.dart';
import 'package:quantum_ide/core/services/model_catalog_service.dart';
import 'local_models_dialog.dart';

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
  List<DiscoveredModel> _models = [];
  bool _isDiscovering = false;
  String? _statusMessage;
  bool _statusOk = true;
  String _selectedCategory = 'Все';

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
    super.dispose();
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
        maxHeight: MediaQuery.of(context).size.height * 0.90,
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
                            ? 'Автономный запуск на устройстве без интернета'
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

          // Search Box
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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

          // Category filter pills for Local models
          if (_isLocalProvider)
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

          const Divider(color: Colors.white10, height: 12),

          // Models List
          Expanded(
            child: _isLocalProvider
                ? _buildLocalModelsList(context, query)
                : _buildCloudModelsList(context, query),
          ),
        ],
      ),
    );
  }

  // ─── Local Models (with parameters, speed, RAM, download actions) ──────────
  Widget _buildLocalModelsList(BuildContext context, String query) {
    final localAiState = ref.watch(localAiServiceProvider);
    final catalogState = ref.watch(modelCatalogProvider);
    final isOllama = widget.providerId == 'ollama';

    // Filter by engine, category and query
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
    // Check if downloaded
    bool isDownloaded = false;
    if (item.isOllama) {
      // Check Ollama downloaded list
      isDownloaded = localAiState.downloadedModels[item.id] == true ||
          localAiState.downloadedModels[item.filename] == true ||
          _models.any((m) => m.id == item.filename || m.id == '${item.filename}:latest');
    } else {
      // Check GGUF catalog or local ai state
      isDownloaded = catalogState.downloadedModels[item.filename] == true ||
          localAiState.downloadedModels[item.id] == true ||
          localAiState.selectedModelFilename == item.filename;
    }

    // Check if currently downloading
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
          // Row 1: Name + Category badge + Size & RAM
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

          // Row 2: Capabilities description
          Text(
            item.capabilities,
            style: GoogleFonts.inter(fontSize: 11.5, color: Colors.white70),
          ),

          const SizedBox(height: 8),

          // Row 3: Parameter badges (Context, Speed, RAM, Quant)
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

          // Row 4: Download / Progress / Action buttons
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
                      final selected = item.isOllama ? item.filename : item.filename;
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
                        // Download through Ollama pull
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
                        // Download GGUF
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

  // ─── Cloud Models (OpenRouter, Google, Claude, DeepSeek, etc.) ────────────
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
              Text(
                'Модели не найдены по запросу "$query"',
                style: GoogleFonts.inter(color: Colors.white54, fontSize: 13),
              ),
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
                      Text(
                        item.id,
                        style: GoogleFonts.jetBrainsMono(fontSize: 11, color: Colors.white38),
                      ),
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
}
