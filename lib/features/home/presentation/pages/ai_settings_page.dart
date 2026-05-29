import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quantum_ide/core/models/ai_provider_config.dart';
import 'package:quantum_ide/core/services/ai_service.dart';
import 'package:quantum_ide/core/services/local_ai_service.dart';
import 'package:quantum_ide/l10n/app_localizations.dart';

// Provider для выбранного провайдера в UI
final _selectedProviderUiProvider = StateProvider<String>((ref) {
  return ref.read(aiServiceProvider).selectedProviderId;
});

class AiSettingsPage extends ConsumerStatefulWidget {
  const AiSettingsPage({super.key});

  @override
  ConsumerState<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends ConsumerState<AiSettingsPage> {
  final Map<String, TextEditingController> _keyControllers = {};
  final Map<String, TextEditingController> _urlControllers = {};
  final Map<String, TextEditingController> _searchControllers = {};
  final Map<String, TextEditingController> _customModelControllers = {};
  final Map<String, bool> _obscured = {};
  // Загруженные модели и состояние
  final Map<String, List<String>> _fetchedModels = {};
  final Map<String, bool> _fetching = {};
  final Map<String, String?> _fetchError = {};
  // Доступность моделей: modelName -> true/false/null (null = не проверена)
  final Map<String, bool?> _modelAvailability = {};
  bool _checkingAvailability = false;

  @override
  void initState() {
    super.initState();
    final svc = ref.read(aiServiceProvider);
    for (final p in AiProviders.all) {
      _keyControllers[p.id] = TextEditingController(text: svc.getApiKey(p.id));
      _urlControllers[p.id] = TextEditingController(text: svc.getBaseUrl(p.id));
      _searchControllers[p.id] = TextEditingController();
      _customModelControllers[p.id] = TextEditingController();
      _obscured[p.id] = true;
      _fetchedModels[p.id] = p.defaultModels;
      _fetching[p.id] = false;
    }
    // Автозагрузка моделей активного провайдера после отрисовки
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final activePid = ref.read(aiServiceProvider).selectedProviderId;
      _fetchModels(activePid);
    });
  }

  @override
  void dispose() {
    for (final c in _keyControllers.values) {
      c.dispose();
    }
    for (final c in _urlControllers.values) {
      c.dispose();
    }
    for (final c in _searchControllers.values) {
      c.dispose();
    }
    for (final c in _customModelControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _fetchModels(String pid) async {
    final svc = ref.read(aiServiceProvider);

    // Automatically save key & URL from input fields first so the fetch uses the user's latest inputs
    final pConfig = AiProviders.byId(pid);
    if (pConfig.requiresApiKey) {
      final key = _keyControllers[pid]?.text.trim() ?? '';
      await svc.setApiKey(pid, key);
    }
    if (pConfig.supportsLocalModels) {
      final url = _urlControllers[pid]?.text.trim() ?? '';
      if (url.isNotEmpty) {
        await svc.setBaseUrl(pid, url);
      }
    }

    setState(() {
      _fetching[pid] = true;
      _fetchError[pid] = null;
    });
    try {
      final models = await svc.fetchAvailableModels(pid);
      if (mounted) {
        _urlControllers[pid]?.text = svc.getBaseUrl(pid);
        setState(() {
          _fetchedModels[pid] = models;
          _fetching[pid] = false;
        });
        // Проверяем доступность всех моделей параллельно
        _checkAvailability(pid, models, svc);
      }
    } catch (e) {
      if (mounted) {
        _urlControllers[pid]?.text = svc.getBaseUrl(pid);
        setState(() {
          _fetchError[pid] = e.toString();
          _fetching[pid] = false;
        });
      }
    }
  }

  Future<void> _checkAvailability(
    String pid,
    List<String> models,
    AIService svc,
  ) async {
    if (_checkingAvailability) return;
    _checkingAvailability = true;
    // Сбрасываем предыдущие результаты для этого провайдера
    for (final m in models) {
      _modelAvailability[m] = null;
    }
    if (mounted) setState(() {});
    // Проверяем параллельно (не более 4 одновременно чтобы не перегрузить)
    const batchSize = 4;
    for (int i = 0; i < models.length; i += batchSize) {
      final end = i + batchSize;
      final batch = models.sublist(
        i,
        end < models.length ? end : models.length,
      );
      final results = await Future.wait(
        batch.map((m) => svc.checkModelAvailability(m, pid)),
      );
      for (int j = 0; j < batch.length; j++) {
        _modelAvailability[batch[j]] = results[j];
      }
      if (mounted) {
        _urlControllers[pid]?.text = svc.getBaseUrl(pid);
        setState(() {});
      }
    }
    _checkingAvailability = false;
  }

  List<String> _filteredModels(String pid) {
    final query = _searchControllers[pid]?.text.toLowerCase() ?? '';
    final models = _fetchedModels[pid] ?? [];
    if (query.isEmpty) return models;
    return models.where((m) => m.toLowerCase().contains(query)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final selectedPid = ref.watch(_selectedProviderUiProvider);
    final svc = ref.read(aiServiceProvider);
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Stack(
        children: [
          // ambient glow
          Positioned(
            top: -80,
            right: -80,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    theme.colorScheme.primary.withValues(alpha: 0.15),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -60,
            left: -60,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    theme.colorScheme.secondary.withValues(alpha: 0.10),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverAppBar(
                pinned: true,
                backgroundColor: theme.scaffoldBackgroundColor,
                elevation: 0,
                leading: IconButton(
                  icon: Icon(
                    LucideIcons.arrow_left,
                    color: theme.colorScheme.onSurface,
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
                title: ShaderMask(
                  shaderCallback: (b) => LinearGradient(
                    colors: [
                      theme.colorScheme.primary,
                      theme.colorScheme.secondary,
                    ],
                  ).createShader(b),
                  child: Text(
                    l10n.aiProviders,
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // Header info
                    _infoCard(),
                    const SizedBox(height: 16),
                    // Provider cards
                    ...AiProviders.all.map(
                      (p) => _providerCard(p, selectedPid, svc),
                    ),
                  ]),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoCard() {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary.withValues(alpha: 0.15),
            theme.colorScheme.secondary.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.info, color: theme.colorScheme.primary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l10n.aiProvidersInfo,
              style: GoogleFonts.inter(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProviderIcon(String providerId) {
    IconData icon;
    List<Color> colors;

    switch (providerId) {
      case 'google':
        icon = LucideIcons.sparkles;
        colors = [Colors.blueAccent, Colors.purpleAccent, Colors.orangeAccent];
        break;
      case 'openai':
        icon = LucideIcons.bot;
        colors = [Colors.teal, const Color(0xFF10A37F)];
        break;
      case 'anthropic':
        icon = LucideIcons.brain;
        colors = [Colors.deepOrange, Colors.orangeAccent];
        break;
      case 'deepseek':
        icon = LucideIcons.cpu;
        colors = [Colors.blue.shade900, Colors.blueAccent];
        break;
      case 'groq':
        icon = LucideIcons.zap;
        colors = [Colors.orangeAccent, Colors.yellow];
        break;
      case 'openrouter':
        icon = LucideIcons.globe;
        colors = [Colors.deepPurple, Colors.indigoAccent];
        break;
      case 'ollama':
        icon = LucideIcons.terminal;
        colors = [Colors.grey.shade800, Colors.black];
        break;
      case 'lmstudio':
        icon = LucideIcons.monitor;
        colors = [Colors.cyanAccent, Colors.blueAccent];
        break;
      case 'local_edge':
        icon = LucideIcons.brain;
        colors = [Colors.purpleAccent, Colors.deepPurpleAccent];
        break;
      default:
        icon = LucideIcons.sparkles;
        colors = [Colors.blue, Colors.purple];
    }

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: colors.first.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(child: Icon(icon, color: Colors.white, size: 22)),
    );
  }

  Widget _providerCard(AiProviderConfig p, String selectedPid, AIService svc) {
    final isSelected = selectedPid == p.id;
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isSelected
            ? theme.colorScheme.primary.withValues(alpha: 0.08)
            : theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isSelected
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurface.withValues(alpha: 0.07),
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: isSelected,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: _buildProviderIcon(p.id),
          title: Text(
            p.displayName,
            style: GoogleFonts.inter(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          subtitle: isSelected
              ? Text(
                  l10n.activeProvider,
                  style: GoogleFonts.inter(
                    color: theme.colorScheme.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                )
              : Text(
                  p.requiresApiKey ? l10n.requiresApiKeyLabel : l10n.localNoKey,
                  style: GoogleFonts.inter(
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.5,
                    ),
                    fontSize: 11,
                  ),
                ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isSelected)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    l10n.activeCaps,
                    style: GoogleFonts.inter(
                      color: theme.colorScheme.primary,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              Icon(
                LucideIcons.chevron_down,
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.5,
                ),
                size: 16,
              ),
            ],
          ),
          children: [
            if (p.id == 'local_edge') ...[
              _buildLocalAiControls(),
              const SizedBox(height: 12),
            ],
            // API Key field
            if (p.requiresApiKey) ...[
              _label(l10n.apiKeyLabel),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(child: _keyField(p.id, p.apiKeyHint)),
                  const SizedBox(width: 8),
                  _saveKeyBtn(p.id, svc),
                ],
              ),
              const SizedBox(height: 12),
            ],
            // Custom URL for local providers
            if (p.supportsLocalModels) ...[
              _label(l10n.serverUrlLabel),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(child: _urlField(p.id, p.baseUrl)),
                  const SizedBox(width: 8),
                  _saveUrlBtn(p.id, svc),
                ],
              ),
              if (p.id == 'ollama') ...[
                const SizedBox(height: 4),
                Text(
                  l10n.ollamaPhoneHint,
                  style: GoogleFonts.inter(
                    color: theme.colorScheme.primary.withValues(alpha: 0.7),
                    fontSize: 10,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
              const SizedBox(height: 12),
            ],
            // Model selector
            Row(
              children: [
                Expanded(child: _label(l10n.modelLabel)),
                _fetchModelsBtn(p.id),
              ],
            ),
            const SizedBox(height: 6),
            // Search field
            _searchField(p.id),
            const SizedBox(height: 8),
            // Models list
            _fetching[p.id] == true
                ? _loadingModels()
                : _modelsList(_filteredModels(p.id), p.id, svc, p),
            if (_fetchError[p.id] != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _fetchError[p.id]!.replaceAll('Exception: ', ''),
                  style: GoogleFonts.inter(
                    color: theme.colorScheme.error,
                    fontSize: 11,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            // Custom model input
            _customModelRow(p.id, svc),
            const SizedBox(height: 12),
            // Activate button
            if (!isSelected)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(LucideIcons.zap, size: 16),
                  label: Text(
                    l10n.activateProvider,
                    style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: theme.colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () async {
                    await svc.setProvider(p.id);
                    ref.read(_selectedProviderUiProvider.notifier).state = p.id;
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(l10n.providerActivated(p.displayName)),
                          backgroundColor: theme.colorScheme.primary,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      );
                    }
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: GoogleFonts.inter(
        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
      ),
    );
  }

  // ─── Кнопка обновить список моделей ───────────────────────────────────────
  Widget _fetchModelsBtn(String pid) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final loading = _fetching[pid] == true;
    return GestureDetector(
      onTap: loading ? null : () => _fetchModels(pid),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          gradient: loading
              ? null
              : LinearGradient(
                  colors: [
                    theme.colorScheme.primary,
                    theme.colorScheme.secondary,
                  ],
                ),
          color: loading
              ? theme.colorScheme.onSurface.withValues(alpha: 0.1)
              : null,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              Icon(
                LucideIcons.refresh_cw,
                size: 12,
                color: theme.colorScheme.onPrimary,
              ),
            const SizedBox(width: 6),
            Text(
              loading ? l10n.searching : l10n.findModels,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: loading
                    ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)
                    : theme.colorScheme.onPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Поиск по моделям ─────────────────────────────────────────────────────
  Widget _searchField(String pid) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return TextField(
      controller: _searchControllers[pid],
      onChanged: (_) => setState(() {}),
      style: GoogleFonts.inter(
        color: theme.colorScheme.onSurface,
        fontSize: 13,
      ),
      decoration: InputDecoration(
        hintText: l10n.searchModelHint,
        hintStyle: GoogleFonts.inter(
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          fontSize: 13,
        ),
        prefixIcon: Icon(
          LucideIcons.search,
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          size: 16,
        ),
        suffixIcon: (_searchControllers[pid]?.text.isNotEmpty ?? false)
            ? IconButton(
                icon: Icon(
                  LucideIcons.x,
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.5,
                  ),
                  size: 14,
                ),
                onPressed: () {
                  _searchControllers[pid]?.clear();
                  setState(() {});
                },
              )
            : null,
        filled: true,
        fillColor: theme.colorScheme.surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.1),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.1),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: theme.colorScheme.primary),
        ),
      ),
    );
  }

  // ─── Ввод кастомной модели ────────────────────────────────────────────────
  Widget _customModelRow(String pid, AIService svc) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _customModelControllers[pid],
            style: GoogleFonts.jetBrainsMono(
              color: theme.colorScheme.onSurface,
              fontSize: 12,
            ),
            decoration: InputDecoration(
              hintText: l10n.customModelHint,
              hintStyle: GoogleFonts.jetBrainsMono(
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.4,
                ),
                fontSize: 12,
              ),
              prefixIcon: Icon(
                LucideIcons.keyboard,
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.5,
                ),
                size: 15,
              ),
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerLow,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.1),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.1),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: theme.colorScheme.secondary),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () async {
            final custom = _customModelControllers[pid]?.text.trim() ?? '';
            if (custom.isEmpty) return;
            await svc.setProvider(pid);
            await svc.setModel(custom);
            ref.read(_selectedProviderUiProvider.notifier).state = pid;
            // Добавим в список если ещё нет
            if (!(_fetchedModels[pid]?.contains(custom) ?? false)) {
              setState(
                () => _fetchedModels[pid] = [
                  custom,
                  ...(_fetchedModels[pid] ?? []),
                ],
              );
            } else {
              setState(() {});
            }
            _customModelControllers[pid]?.clear();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(l10n.modelInstalled(custom)),
                  backgroundColor: theme.colorScheme.secondary,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              );
            }
          },
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: theme.colorScheme.secondary.withValues(alpha: 0.3),
              ),
            ),
            child: Icon(
              LucideIcons.check,
              color: theme.colorScheme.secondary,
              size: 18,
            ),
          ),
        ),
      ],
    );
  }

  Widget _keyField(String pid, String hint) {
    final theme = Theme.of(context);
    return TextField(
      controller: _keyControllers[pid],
      obscureText: _obscured[pid] ?? true,
      style: GoogleFonts.jetBrainsMono(
        color: theme.colorScheme.onSurface,
        fontSize: 13,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.jetBrainsMono(
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          fontSize: 13,
        ),
        filled: true,
        fillColor: theme.colorScheme.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.1),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.1),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: theme.colorScheme.primary),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        suffixIcon: IconButton(
          icon: Icon(
            _obscured[pid] == true ? LucideIcons.eye : LucideIcons.eye_off,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            size: 16,
          ),
          onPressed: () =>
              setState(() => _obscured[pid] = !(_obscured[pid] ?? true)),
        ),
      ),
    );
  }

  Widget _urlField(String pid, String placeholder) {
    final theme = Theme.of(context);
    return TextField(
      controller: _urlControllers[pid],
      style: GoogleFonts.jetBrainsMono(
        color: theme.colorScheme.onSurface,
        fontSize: 12,
      ),
      decoration: InputDecoration(
        hintText: placeholder,
        hintStyle: GoogleFonts.jetBrainsMono(
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          fontSize: 12,
        ),
        filled: true,
        fillColor: theme.colorScheme.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.1),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.1),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: theme.colorScheme.secondary),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
      ),
    );
  }

  Widget _saveKeyBtn(String pid, AIService svc) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return GestureDetector(
      onTap: () async {
        final key = _keyControllers[pid]?.text ?? '';
        await svc.setApiKey(pid, key);
        // Обновляем список моделей
        _fetchModels(pid);
        if (mounted) {
          HapticFeedback.mediumImpact();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.keySaved),
              backgroundColor: theme.colorScheme.primary,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.3),
          ),
        ),
        child: Icon(
          LucideIcons.save,
          color: theme.colorScheme.primary,
          size: 18,
        ),
      ),
    );
  }

  Widget _saveUrlBtn(String pid, AIService svc) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return GestureDetector(
      onTap: () async {
        final url = _urlControllers[pid]?.text ?? '';
        await svc.setBaseUrl(pid, url);
        _fetchModels(pid);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.urlSaved),
              backgroundColor: theme.colorScheme.primary,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: theme.colorScheme.secondary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: theme.colorScheme.secondary.withValues(alpha: 0.3),
          ),
        ),
        child: Icon(
          LucideIcons.link,
          color: theme.colorScheme.secondary,
          size: 18,
        ),
      ),
    );
  }

  Widget _loadingModels() {
    final theme = Theme.of(context);
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
        ),
      ),
      child: Center(
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }

  Widget _modelsList(
    List<String> models,
    String pid,
    AIService svc,
    AiProviderConfig p,
  ) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final currentModel = svc.selectedModel;
    final isActive = svc.selectedProviderId == pid;

    if (models.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
          ),
        ),
        child: Center(
          child: Text(
            l10n.modelsNotFound,
            style: GoogleFonts.inter(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              fontSize: 12,
            ),
          ),
        ),
      );
    }

    // Legend
    final hasChecks = models.any((m) => _modelAvailability.containsKey(m));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasChecks) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                _dot(Colors.green),
                const SizedBox(width: 4),
                Text(
                  l10n.available,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 12),
                _dot(Colors.orange),
                const SizedBox(width: 4),
                Text(
                  l10n.quotaLimit,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 12),
                _dot(Colors.redAccent),
                const SizedBox(width: 4),
                Text(
                  l10n.unavailable,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
            ),
          ),
          child: Column(
            children: models.asMap().entries.map((e) {
              final i = e.key;
              final m = e.value;
              final isSel = isActive && currentModel == m;
              final avail =
                  _modelAvailability[m]; // null=checking, true=ok, false=no

              return InkWell(
                borderRadius: BorderRadius.circular(i == 0 ? 10 : 0),
                onTap: () async {
                  await svc.setProvider(pid);
                  await svc.setModel(m);
                  ref.read(_selectedProviderUiProvider.notifier).state = pid;
                  setState(() {});
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Model: $m'),
                        backgroundColor: theme.colorScheme.primary,
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(seconds: 1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    );
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isSel
                        ? theme.colorScheme.primary.withValues(alpha: 0.1)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: i < models.length - 1
                        ? Border(
                            bottom: BorderSide(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.05,
                              ),
                            ),
                          )
                        : null,
                  ),
                  child: Row(
                    children: [
                      // Availability dot
                      if (avail == null && hasChecks)
                        SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.3),
                          ),
                        )
                      else if (avail == true)
                        _dot(Colors.green)
                      else if (avail == false)
                        _dot(Colors.redAccent)
                      else
                        _dot(
                          theme.colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.15,
                          ),
                        ),
                      const SizedBox(width: 8),
                      Icon(
                        LucideIcons.sparkles,
                        size: 13,
                        color: isSel
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant.withValues(
                                alpha: 0.3,
                              ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          m,
                          style: GoogleFonts.jetBrainsMono(
                            color: isSel
                                ? theme.colorScheme.onSurface
                                : theme.colorScheme.onSurfaceVariant,
                            fontSize: 12,
                            fontWeight: isSel
                                ? FontWeight.w700
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                      if (avail == true)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            l10n.availableCaps,
                            style: GoogleFonts.inter(
                              fontSize: 8,
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      if (isSel) ...[
                        const SizedBox(width: 6),
                        Icon(
                          LucideIcons.check,
                          size: 14,
                          color: theme.colorScheme.primary,
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildLocalAiControls() {
    final svc = ref.read(aiServiceProvider);
    final currentEngine = svc.selectedLocalEngine;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('ДВИЖОК ЛОКАЛЬНОГО ИИ'),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
            ),
          ),
          padding: const EdgeInsets.all(4),
          child: Row(
            children: LocalAiEngine.values.map((eng) {
              final isEngSelected = currentEngine == eng;
              return Expanded(
                child: GestureDetector(
                  onTap: () async {
                    await svc.setLocalEngine(eng);
                    if (mounted) {
                      _urlControllers['local_edge']?.text = svc.getBaseUrl(
                        'local_edge',
                      );
                      setState(() {});
                      // Fetch models for the new engine
                      _fetchModels('local_edge');
                    }
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: isEngSelected
                          ? theme.colorScheme.primary
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      eng.displayName,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isEngSelected
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 16),
        if (currentEngine == LocalAiEngine.llamaServer) ...[
          _buildLlamaServerControls(),
        ] else if (currentEngine == LocalAiEngine.ollama) ...[
          _buildExternalEngineNote(
            icon: LucideIcons.terminal,
            title: 'Ollama запущен локально',
            description:
                'Убедитесь, что Ollama запущена на вашей системе. Вы можете запустить её командой "ollama serve" и загрузить нужные модели командой "ollama pull <модель>".',
          ),
        ] else if (currentEngine == LocalAiEngine.lmStudio) ...[
          _buildExternalEngineNote(
            icon: LucideIcons.monitor,
            title: 'LM Studio запущен локально',
            description:
                'Убедитесь, что сервер LM Studio запущен. Вы можете включить Local Server в приложении LM Studio и загрузить нужную модель.',
          ),
        ],
      ],
    );
  }

  Widget _buildExternalEngineNote({
    required IconData icon,
    required String title,
    required String description,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: theme.colorScheme.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLlamaServerControls() {
    return Consumer(
      builder: (context, ref, child) {
        final state = ref.watch(localAiServiceProvider);
        final notifier = ref.read(localAiServiceProvider.notifier);
        final theme = Theme.of(context);
        final svc = ref.watch(aiServiceProvider);
        final currentEngine = svc.settings.selectedLocalEngine;
        final isOllama = currentEngine == LocalAiEngine.ollama;
        final engineModels = availableLocalModels.where((m) => m.engine == currentEngine).toList();

        // ─── Ollama: not connected ───
        if (isOllama && !state.isBinaryInstalled) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(LucideIcons.terminal, color: theme.colorScheme.primary, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Ollama не обнаружен',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Установите Ollama на устройстве и убедитесь что он запущен. URL можно изменить выше.',
                      style: GoogleFonts.inter(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => notifier.checkStatus(),
                        icon: const Icon(LucideIcons.refresh_cw, size: 16),
                        label: const Text('Проверить подключение'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.colorScheme.primary,
                          foregroundColor: theme.colorScheme.onPrimary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                    if (state.error != null) ...[
                      const SizedBox(height: 8),
                      Text(state.error!, style: GoogleFonts.inter(color: theme.colorScheme.error, fontSize: 11)),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _label('ДОСТУПНЫЕ OLLAMA МОДЕЛИ'),
              const SizedBox(height: 8),
              ..._buildModelCards(engineModels, state, notifier, theme),
            ],
          );
        }

        // ─── Llama-server: binary not installed ───
        if (!isOllama && !state.isBinaryInstalled) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(LucideIcons.cpu, color: theme.colorScheme.primary, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Требуется установка llama-server',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Для запуска локальных моделей ИИ необходим движок llama-server. Нажмите кнопку ниже, чтобы установить его автоматически.',
                  style: GoogleFonts.inter(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: state.isBinaryInstalling ? null : () => notifier.installBinary(),
                    icon: state.isBinaryInstalling
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Colors.white),
                            ),
                          )
                        : const Icon(LucideIcons.download, size: 16),
                    label: Text(state.isBinaryInstalling ? 'Установка...' : 'Установить Llama Server Runtime'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: theme.colorScheme.onPrimary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                if (state.error != null) ...[
                  const SizedBox(height: 8),
                  Text(state.error!, style: GoogleFonts.inter(color: theme.colorScheme.error, fontSize: 11)),
                ],
              ],
            ),
          );
        }

        // ─── Main: model list + server controls ───
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label(isOllama ? 'OLLAMA МОДЕЛИ' : 'ЛОКАЛЬНЫЕ ИИ МОДЕЛИ'),
            const SizedBox(height: 8),
            ..._buildModelCards(engineModels, state, notifier, theme),
            const SizedBox(height: 16),
            _label('СТАТУС И УПРАВЛЕНИЕ СЕРВЕРОМ'),
            const SizedBox(height: 8),
            if (!state.isModelDownloaded) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.colorScheme.onSurface.withValues(alpha: 0.08)),
                ),
                child: Text(
                  isOllama
                      ? 'Скачайте хотя бы одну Ollama-модель, чтобы начать работу.'
                      : 'Загрузите хотя бы одну модель выше, чтобы запустить локальный сервер.',
                  style: GoogleFonts.inter(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.colorScheme.onSurface.withValues(alpha: 0.08)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isOllama ? 'Ollama' : 'Локальный сервер llama-server',
                              style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                _dot(state.isRunning
                                    ? Colors.green
                                    : (state.isStarting ? Colors.orange : Colors.grey)),
                                const SizedBox(width: 6),
                                Text(
                                  state.isRunning
                                      ? (isOllama ? 'Подключён' : 'Запущен (порт 8080)')
                                      : (state.isStarting ? 'Запуск...' : 'Остановлен'),
                                  style: GoogleFonts.inter(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ],
                        ),
                        if (isOllama)
                          ElevatedButton.icon(
                            onPressed: () => notifier.checkStatus(),
                            icon: const Icon(LucideIcons.refresh_cw, size: 14),
                            label: const Text('Обновить'),
                            style: ElevatedButton.styleFrom(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          )
                        else
                          Row(
                            children: [
                              if (!state.isRunning && !state.isStarting)
                                ElevatedButton.icon(
                                  onPressed: () => notifier.startServer(),
                                  icon: const Icon(LucideIcons.play, size: 14),
                                  label: const Text('Старт'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: theme.colorScheme.primary,
                                    foregroundColor: theme.colorScheme.onPrimary,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                )
                              else if (state.isStarting)
                                const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              else
                                ElevatedButton.icon(
                                  onPressed: () => notifier.stopServer(),
                                  icon: const Icon(LucideIcons.square, size: 14),
                                  label: const Text('Стоп'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: theme.colorScheme.error,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                ),
                            ],
                          ),
                      ],
                    ),
                    if (state.error != null) ...[
                      const SizedBox(height: 8),
                      Text(state.error!, style: GoogleFonts.inter(color: theme.colorScheme.error, fontSize: 11)),
                    ],
                    if (!isOllama && state.logs.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        height: 120,
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: theme.colorScheme.onSurface.withValues(alpha: 0.1)),
                        ),
                        child: SingleChildScrollView(
                          reverse: true,
                          child: SelectionArea(
                            child: Text(
                              state.logs,
                              style: GoogleFonts.jetBrainsMono(color: Colors.lightGreenAccent, fontSize: 10),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  List<Widget> _buildModelCards(
    List<LocalModelInfo> models,
    LocalAiState state,
    LocalAiService notifier,
    ThemeData theme,
  ) {
    return models.map((model) {
      final isDownloaded = state.downloadedModels[model.id] == true;
      final isDownloading = state.downloadingModelId == model.id;
      final isAnyDownloading = state.downloadingModelId != null;
      final isActive = state.selectedModelFilename == model.filename;

      return Container(
        key: ValueKey(model.id),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive
                ? theme.colorScheme.primary.withValues(alpha: 0.5)
                : theme.colorScheme.onSurface.withValues(alpha: 0.08),
            width: isActive ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              model.name,
                              style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ),
                          if (isActive && isDownloaded) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'АКТИВНА',
                                style: GoogleFonts.inter(
                                  color: theme.colorScheme.primary,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        model.description,
                        style: GoogleFonts.inter(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    _metaChip(theme, LucideIcons.hard_drive, '${model.sizeGb.toStringAsFixed(2)} ГБ'),
                    const SizedBox(width: 8),
                    _metaChip(theme, LucideIcons.cpu, '~${model.ramRequiredGb.toStringAsFixed(1)} ГБ ОЗУ'),
                  ],
                ),
                if (isDownloading) ...[
                  IconButton(
                    icon: Icon(LucideIcons.circle_stop, color: theme.colorScheme.error, size: 18),
                    onPressed: () => notifier.cancelDownload(),
                  ),
                ] else if (isDownloaded) ...[
                  Row(
                    children: [
                      if (!isActive)
                        TextButton(
                          onPressed: () => notifier.selectModel(model.id),
                          child: Text('Выбрать', style: GoogleFonts.inter(fontSize: 12)),
                        ),
                      IconButton(
                        icon: Icon(LucideIcons.trash_2, color: theme.colorScheme.error, size: 18),
                        onPressed: () => notifier.deleteModel(model.id),
                      ),
                    ],
                  ),
                ] else ...[
                  ElevatedButton.icon(
                    onPressed: isAnyDownloading ? null : () => notifier.downloadModel(model.id),
                    icon: const Icon(LucideIcons.download, size: 12),
                    label: Text('Скачать', style: GoogleFonts.inter(fontSize: 11)),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                  ),
                ],
              ],
            ),
            if (isDownloading) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      value: state.downloadProgress,
                      backgroundColor: theme.colorScheme.surfaceContainerHighest,
                      color: theme.colorScheme.primary,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${(state.downloadProgress * 100).toStringAsFixed(0)}%',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      );
    }).toList();
  }

  Widget _metaChip(ThemeData theme, IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(icon, size: 11, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 10,
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
  Widget _dot(Color color) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}
