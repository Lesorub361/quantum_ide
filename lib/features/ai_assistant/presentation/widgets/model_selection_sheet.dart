import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:quantum_ide/core/models/ai_provider_config.dart';
import 'package:quantum_ide/core/services/ai_service.dart';

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
      _statusMessage = 'Поиск доступных моделей через API...';
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

    final filteredModels = query.isEmpty
        ? _models
        : _models.where((m) {
            return m.id.toLowerCase().contains(query) ||
                m.displayName.toLowerCase().contains(query);
          }).toList();

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF131824),
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
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
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
                        'Выбор модели ИИ',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        '${provider.displayName} · ${_models.length} моделей',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Colors.white54,
                        ),
                      ),
                    ],
                  ),
                ),
                // Refresh / Discover button
                TextButton.icon(
                  onPressed: _isDiscovering ? null : _discover,
                  icon: _isDiscovering
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.cyanAccent,
                          ),
                        )
                      : const Icon(LucideIcons.refresh_cw, size: 14, color: Colors.cyanAccent),
                  label: Text(
                    _isDiscovering ? 'Поиск...' : 'API Каталог',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.cyanAccent,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.cyanAccent.withValues(alpha: 0.12),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: Colors.cyanAccent.withValues(alpha: 0.3)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Поиск модели или ввод своего ID...',
                hintStyle: GoogleFonts.inter(color: Colors.white38, fontSize: 13),
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
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Colors.white12),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Colors.white12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Colors.cyanAccent),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                isDense: true,
              ),
            ),
          ),

          // Status message (if discovering or discovered)
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

          // Custom Model Selection Action (if user typed something)
          if (query.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: InkWell(
                onTap: () {
                  final customId = _searchController.text.trim();
                  Navigator.pop(context, customId);
                },
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.sparkles, size: 16, color: Color(0xFFF59E0B)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Использовать указанный ID модели:',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: Colors.white70,
                              ),
                            ),
                            Text(
                              _searchController.text.trim(),
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFFF59E0B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(LucideIcons.arrow_right, size: 16, color: Color(0xFFF59E0B)),
                    ],
                  ),
                ),
              ),
            ),

          const Divider(color: Colors.white10, height: 16),

          // Models List
          Expanded(
            child: filteredModels.isEmpty
                ? Center(
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
                          const SizedBox(height: 6),
                          Text(
                            'Вы можете нажать кнопку выше для использования введенного ID',
                            style: GoogleFonts.inter(color: Colors.white38, fontSize: 11),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    itemCount: filteredModels.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final item = filteredModels[index];
                      final isSelected = item.id == widget.currentModel;

                      return InkWell(
                        onTap: () => Navigator.pop(context, item.id),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.cyanAccent.withValues(alpha: 0.12)
                                : Colors.white.withValues(alpha: 0.03),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected
                                  ? Colors.cyanAccent.withValues(alpha: 0.5)
                                  : Colors.white.withValues(alpha: 0.06),
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
                                              border: Border.all(
                                                color: const Color(0xFF10B981).withValues(alpha: 0.4),
                                                width: 0.7,
                                              ),
                                            ),
                                            child: Text(
                                              'FREE',
                                              style: GoogleFonts.inter(
                                                color: const Color(0xFF10B981),
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      item.id,
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 11,
                                        color: Colors.white38,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (isSelected)
                                const Icon(
                                  Icons.check_circle_rounded,
                                  size: 18,
                                  color: Colors.cyanAccent,
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
