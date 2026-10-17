import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quantum_ide/core/models/agent_activity_item.dart';
import 'package:quantum_ide/core/services/cli_auth_service.dart';
import 'package:quantum_ide/core/services/openrouter_models_service.dart';

class CliAgentModelPickerDialog extends ConsumerStatefulWidget {
  final AgentKind kind;
  final String currentModel;
  final void Function(String modelId) onSelected;

  const CliAgentModelPickerDialog({
    super.key,
    required this.kind,
    required this.currentModel,
    required this.onSelected,
  });

  static Future<void> show(
    BuildContext context, {
    required AgentKind kind,
    required String currentModel,
    required void Function(String modelId) onSelected,
  }) {
    return showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (_) => CliAgentModelPickerDialog(
        kind: kind,
        currentModel: currentModel,
        onSelected: onSelected,
      ),
    );
  }

  @override
  ConsumerState<CliAgentModelPickerDialog> createState() => _CliAgentModelPickerDialogState();
}

enum _ModelFilter { all, freeOnly, coding, reasoning, largeContext }

class _CliAgentModelPickerDialogState extends ConsumerState<CliAgentModelPickerDialog> {
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _customModelCtrl = TextEditingController();

  _ModelFilter _activeFilter = _ModelFilter.all;
  List<OpenRouterModelInfo> _models = [];
  bool _isLoadingModels = true;
  OpenRouterAccountInfo? _accountInfo;
  bool _isLoadingAccount = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadModels();
    _loadAccountInfo();
    _searchCtrl.addListener(() {
      setState(() {
        _searchQuery = _searchCtrl.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _customModelCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadModels({bool forceRefresh = false}) async {
    setState(() => _isLoadingModels = true);
    final svc = ref.read(openRouterModelsServiceProvider);
    final list = await svc.getModels(forceRefresh: forceRefresh);
    if (mounted) {
      setState(() {
        _models = list;
        _isLoadingModels = false;
      });
    }
  }

  Future<void> _loadAccountInfo() async {
    final auth = ref.read(cliAuthProvider);
    final key = auth.openRouterApiKey ??
        (widget.kind == AgentKind.deepseekHarness ? auth.deepseekApiKey : null) ??
        '';

    if (key.isEmpty || !key.startsWith('sk-or-')) {
      return;
    }

    setState(() => _isLoadingAccount = true);
    final svc = ref.read(openRouterModelsServiceProvider);
    final info = await svc.fetchAccountInfo(key);
    if (mounted) {
      setState(() {
        _accountInfo = info;
        _isLoadingAccount = false;
      });
    }
  }

  List<OpenRouterModelInfo> get _filteredModels {
    return _models.where((m) {
      if (_searchQuery.isNotEmpty) {
        final match = m.id.toLowerCase().contains(_searchQuery) ||
            m.name.toLowerCase().contains(_searchQuery) ||
            m.description.toLowerCase().contains(_searchQuery) ||
            m.providerName.toLowerCase().contains(_searchQuery);
        if (!match) return false;
      }

      switch (_activeFilter) {
        case _ModelFilter.all:
          return true;
        case _ModelFilter.freeOnly:
          return m.isFree;
        case _ModelFilter.coding:
          return m.isCoding;
        case _ModelFilter.reasoning:
          return m.isReasoning;
        case _ModelFilter.largeContext:
          return m.contextLength >= 500000;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 700;
    final filtered = _filteredModels;
    final freeCount = _models.where((m) => m.isFree).length;

    return Dialog(
      backgroundColor: const Color(0xFF131824),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
      ),
      insetPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 36,
        vertical: isMobile ? 16 : 28,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 680,
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Top Header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 16, 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: widget.kind.brandColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(widget.kind.icon, size: 20, color: widget.kind.brandColor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Выбор модели: ${widget.kind.title}',
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.cyanAccent.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.3)),
                              ),
                              child: Text(
                                '${_models.length} доступно',
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.cyanAccent,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          'Характеристики, лимиты контекста, рассуждения и бесплатные квоты',
                          style: GoogleFonts.inter(fontSize: 11, color: Colors.white54),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(LucideIcons.x, size: 18, color: Colors.white54),
                  ),
                ],
              ),
            ),

            // ── Account & Limits Banner (OpenRouter) ──
            if (_accountInfo != null) _buildAccountBanner(_accountInfo!),

            // ── Search & Filter Controls ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Column(
                children: [
                  // Search Bar
                  Container(
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white12),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      children: [
                        const Icon(LucideIcons.search, size: 15, color: Colors.white38),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _searchCtrl,
                            style: GoogleFonts.inter(fontSize: 12.5, color: Colors.white),
                            decoration: InputDecoration(
                              hintText: 'Поиск модели по названию, провайдеру или ID...',
                              hintStyle: GoogleFonts.inter(fontSize: 12, color: Colors.white38),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                        if (_searchQuery.isNotEmpty)
                          IconButton(
                            icon: const Icon(LucideIcons.x, size: 14, color: Colors.white38),
                            onPressed: () => _searchCtrl.clear(),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Filter Chips
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterChip('Все', _ModelFilter.all, count: _models.length),
                        _buildFilterChip('🎁 Бесплатные', _ModelFilter.freeOnly, count: freeCount, highlight: true),
                        _buildFilterChip('💻 Для кода', _ModelFilter.coding),
                        _buildFilterChip('🧠 Рассуждения (R1)', _ModelFilter.reasoning),
                        _buildFilterChip('🚀 1M+ Контекст', _ModelFilter.largeContext),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const Divider(color: Colors.white10, height: 16),

            // ── Model List ──
            Expanded(
              child: _isLoadingModels
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyanAccent),
                    )
                  : filtered.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                          itemCount: filtered.length,
                          itemBuilder: (ctx, i) {
                            final m = filtered[i];
                            final isSelected = m.id == widget.currentModel;
                            return _buildModelCard(m, isSelected);
                          },
                        ),
            ),

            // ── Custom Model ID Footer ──
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              decoration: BoxDecoration(
                color: const Color(0xFF0C101A),
                border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 34,
                      child: TextField(
                        controller: _customModelCtrl,
                        style: GoogleFonts.jetBrainsMono(fontSize: 11.5, color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Или введите свой slug (например: deepseek/deepseek-chat)',
                          hintStyle: GoogleFonts.inter(fontSize: 11, color: Colors.white38),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.05),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      final custom = _customModelCtrl.text.trim();
                      if (custom.isNotEmpty) {
                        widget.onSelected(custom);
                        Navigator.pop(context);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.cyanAccent,
                      foregroundColor: Colors.black,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: Text('Выбрать', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountBanner(OpenRouterAccountInfo info) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF14243A),
            const Color(0xFF112033).withValues(alpha: 0.9),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(LucideIcons.wallet, size: 14, color: Colors.cyanAccent),
                  const SizedBox(width: 6),
                  Text(
                    'Аккаунт OpenRouter: ',
                    style: GoogleFonts.inter(fontSize: 11, color: Colors.white70),
                  ),
                  Text(
                    info.label,
                    style: GoogleFonts.jetBrainsMono(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.cyanAccent),
                  ),
                ],
              ),
              InkWell(
                onTap: () {
                  _loadAccountInfo();
                  _loadModels(forceRefresh: true);
                },
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Row(
                    children: [
                      if (_isLoadingAccount)
                        const SizedBox(
                          width: 11,
                          height: 11,
                          child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.cyanAccent),
                        )
                      else
                        const Icon(LucideIcons.refresh_cw, size: 11, color: Colors.white54),
                      const SizedBox(width: 4),
                      Text(
                        'Обновить',
                        style: GoogleFonts.inter(fontSize: 10, color: Colors.white54),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              // Free Limit
              Expanded(
                flex: 3,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.greenAccent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Бесплатные запросы сегодня:',
                            style: GoogleFonts.inter(fontSize: 10, color: Colors.white60),
                          ),
                          Text(
                            '${info.freeRemaining} / ${info.freeLimit}',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.greenAccent,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: (info.freeRemaining / info.freeLimit).clamp(0.0, 1.0),
                          backgroundColor: Colors.white10,
                          valueColor: const AlwaysStoppedAnimation(Colors.greenAccent),
                          minHeight: 4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Paid Credits
              Expanded(
                flex: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Баланс кредитов:',
                        style: GoogleFonts.inter(fontSize: 10, color: Colors.white60),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '\$${info.balance.toStringAsFixed(2)}',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: info.balance > 0 ? Colors.cyanAccent : Colors.white38,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, _ModelFilter filter, {int? count, bool highlight = false}) {
    final isSelected = _activeFilter == filter;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: () => setState(() => _activeFilter = filter),
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: isSelected
                ? (highlight ? Colors.greenAccent.withValues(alpha: 0.25) : Colors.cyanAccent.withValues(alpha: 0.2))
                : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected
                  ? (highlight ? Colors.greenAccent : Colors.cyanAccent)
                  : Colors.white10,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? Colors.white : Colors.white60,
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.white24 : Colors.white10,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$count',
                    style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.white70),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModelCard(OpenRouterModelInfo m, bool isSelected) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected
            ? widget.kind.brandColor.withValues(alpha: 0.12)
            : const Color(0xFF161C2C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected
              ? widget.kind.brandColor.withValues(alpha: 0.7)
              : Colors.white.withValues(alpha: 0.08),
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: () {
          widget.onSelected(m.id);
          Navigator.pop(context);
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Row: Title, Badges, Selected Check
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
                                m.name,
                                style: GoogleFonts.inter(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            if (m.isFree)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: Colors.greenAccent.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.6)),
                                ),
                                child: Text(
                                  'FREE',
                                  style: GoogleFonts.inter(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.greenAccent,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          m.id,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10.5,
                            color: Colors.white54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (isSelected)
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: widget.kind.brandColor,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(LucideIcons.check, size: 12, color: Colors.black),
                    ),
                ],
              ),

              const SizedBox(height: 8),

              // Middle: Tags (Context, Modality, Capabilities)
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  // Context Window Badge
                  _buildTag(
                    icon: LucideIcons.book_open,
                    label: '${m.formattedContext} context',
                    color: Colors.blueAccent,
                  ),

                  // Provider
                  _buildTag(
                    icon: LucideIcons.cpu,
                    label: m.providerName,
                    color: Colors.purpleAccent,
                  ),

                  if (m.isCoding)
                    _buildTag(
                      icon: LucideIcons.code,
                      label: 'Code Specialist',
                      color: Colors.amberAccent,
                    ),

                  if (m.isReasoning)
                    _buildTag(
                      icon: LucideIcons.brain,
                      label: 'Reasoning / Thinking',
                      color: Colors.cyanAccent,
                    ),

                  if (m.modality.contains('image'))
                    _buildTag(
                      icon: LucideIcons.image,
                      label: 'Vision',
                      color: Colors.orangeAccent,
                    ),
                ],
              ),

              // Bottom: Description
              if (m.description.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  m.description,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: Colors.white60,
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTag({required IconData icon, required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.search_x, size: 36, color: Colors.white24),
            const SizedBox(height: 8),
            Text(
              'Модели по запросу "$_searchQuery" не найдены',
              style: GoogleFonts.inter(fontSize: 13, color: Colors.white60),
            ),
            const SizedBox(height: 6),
            Text(
              'Вы можете ввести точный slug модели в поле ниже',
              style: GoogleFonts.inter(fontSize: 11, color: Colors.white38),
            ),
          ],
        ),
      ),
    );
  }
}
