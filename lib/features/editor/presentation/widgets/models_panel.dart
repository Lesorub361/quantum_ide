import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quantum_ide/core/services/model_catalog_service.dart';
import 'package:quantum_ide/core/services/image_gen_service.dart';
import 'package:quantum_ide/core/services/chat_settings_service.dart';
import 'package:quantum_ide/core/services/local_ai_service.dart';
import 'package:quantum_ide/l10n/app_localizations.dart';

class ModelsPanel extends ConsumerStatefulWidget {
  const ModelsPanel({super.key});

  @override
  ConsumerState<ModelsPanel> createState() => _ModelsPanelState();
}

class _ModelsPanelState extends ConsumerState<ModelsPanel> {
  ModelCategory _selectedCategory = ModelCategory.text;
  bool _showSettings = false;

  @override
  Widget build(BuildContext context) {
    final catalogState = ref.watch(modelCatalogProvider);
    final imageGenState = ref.watch(imageGenProvider);
    final chatSettings = ref.watch(chatSettingsProvider);
    final localAi = ref.watch(localAiServiceProvider);
    final l10n = AppLocalizations.of(context)!;

    return Container(
      color: const Color(0xFF0D0F14).withValues(alpha: 0.7),
      child: Column(
        children: [
          _buildHeader(l10n),
          _buildStatusBar(localAi, imageGenState),
          _buildCategoryBar(l10n),
          if (_showSettings)
            _buildSettingsPanel(chatSettings, l10n)
          else
            Expanded(
              child: _buildModelList(catalogState, imageGenState, l10n),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [Colors.cyanAccent, Colors.greenAccent],
            ).createShader(bounds),
            child: const Icon(LucideIcons.cpu, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Local Models',
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _showSettings = !_showSettings),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _showSettings
                    ? Colors.cyanAccent.withValues(alpha: 0.15)
                    : Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: _showSettings
                      ? Colors.cyanAccent.withValues(alpha: 0.3)
                      : Colors.white.withValues(alpha: 0.1),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.settings, size: 12, color: _showSettings ? Colors.cyanAccent : Colors.white54),
                  const SizedBox(width: 4),
                  Text(
                    'Settings',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      color: _showSettings ? Colors.cyanAccent : Colors.white54,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar(LocalAiState localAi, ImageGenState imageGen) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: localAi.isRunning
            ? Colors.greenAccent.withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: localAi.isRunning
              ? Colors.greenAccent.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.05),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: localAi.isRunning ? Colors.greenAccent : Colors.white38,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              localAi.isRunning
                  ? 'Server: Running'
                  : localAi.isStarting
                      ? 'Server: Starting...'
                      : 'Server: Stopped',
              style: GoogleFonts.inter(
                color: localAi.isRunning
                    ? Colors.greenAccent
                    : localAi.isStarting
                        ? Colors.orangeAccent
                        : Colors.white54,
                fontSize: 10,
              ),
            ),
          ),
          if (localAi.isRunning)
            GestureDetector(
              onTap: () => ref.read(localAiServiceProvider.notifier).stopServer(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('Stop', style: GoogleFonts.inter(color: Colors.redAccent, fontSize: 9, fontWeight: FontWeight.bold)),
              ),
            )
          else if (!localAi.isStarting)
            GestureDetector(
              onTap: () => ref.read(localAiServiceProvider.notifier).startServer(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.greenAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('Start', style: GoogleFonts.inter(color: Colors.greenAccent, fontSize: 9, fontWeight: FontWeight.bold)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCategoryBar(AppLocalizations l10n) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          _buildCategoryChip(ModelCategory.text, 'Text', LucideIcons.message_square),
          const SizedBox(width: 6),
          _buildCategoryChip(ModelCategory.image, 'Image', LucideIcons.image),
          const SizedBox(width: 6),
          _buildCategoryChip(ModelCategory.vision, 'Vision', LucideIcons.eye),
        ],
      ),
    );
  }

  Widget _buildCategoryChip(ModelCategory category, String label, IconData icon) {
    final isSelected = _selectedCategory == category;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedCategory = category),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? Colors.cyanAccent.withValues(alpha: 0.12)
                : Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? Colors.cyanAccent.withValues(alpha: 0.3)
                  : Colors.white.withValues(alpha: 0.05),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 12, color: isSelected ? Colors.cyanAccent : Colors.white38),
              const SizedBox(width: 4),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 10,
                  color: isSelected ? Colors.cyanAccent : Colors.white54,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModelList(ModelCatalogState catalog, ImageGenState imageGen, AppLocalizations l10n) {
    final models = catalog.models.where((m) => m.category == _selectedCategory).toList();

    if (models.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.package_search, size: 48, color: Colors.white.withValues(alpha: 0.1)),
            const SizedBox(height: 12),
            Text('No models available', style: GoogleFonts.inter(color: Colors.white38, fontSize: 13)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: models.length,
      itemBuilder: (context, index) {
        final model = models[index];
        final isDownloaded = catalog.downloadedModels[model.filename] == true;
        final downloadInfo = catalog.downloads[model.filename];

        return _buildModelCard(model, isDownloaded, downloadInfo, imageGen);
      },
    );
  }

  Widget _buildModelCard(AiCatalogModel model, bool isDownloaded, ModelDownloadInfo? downloadInfo, ImageGenState imageGen) {
    final isDownloading = downloadInfo?.status == DownloadStatus.downloading;
    final categoryColor = model.category == ModelCategory.image
        ? Colors.purpleAccent
        : model.category == ModelCategory.vision
            ? Colors.orangeAccent
            : Colors.cyanAccent;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: categoryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  model.category == ModelCategory.image ? LucideIcons.image : LucideIcons.brain,
                  size: 16,
                  color: categoryColor,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      model.name,
                      style: GoogleFonts.inter(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Row(
                      children: [
                        Text(
                          model.size,
                          style: GoogleFonts.jetBrainsMono(color: Colors.white38, fontSize: 9),
                        ),
                        if (model.isVision) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.purpleAccent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text('VISION', style: GoogleFonts.inter(color: Colors.purpleAccent, fontSize: 7, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              _buildModelAction(model, isDownloaded, isDownloading, downloadInfo),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            model.description,
            style: GoogleFonts.inter(color: Colors.white38, fontSize: 9.5),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (isDownloading && downloadInfo != null) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: downloadInfo.progress,
                backgroundColor: Colors.white.withValues(alpha: 0.05),
                valueColor: AlwaysStoppedAnimation(categoryColor),
                minHeight: 3,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${(downloadInfo.progress * 100).toStringAsFixed(1)}% • ${ModelCatalogNotifier.formatBytes(downloadInfo.downloadedBytes)} / ${ModelCatalogNotifier.formatBytes(downloadInfo.totalBytes)}',
                  style: GoogleFonts.jetBrainsMono(color: Colors.white38, fontSize: 8),
                ),
                if (downloadInfo.speed > 0)
                  Text(
                    '${ModelCatalogNotifier.formatSpeed(downloadInfo.speed)}',
                    style: GoogleFonts.jetBrainsMono(color: Colors.greenAccent, fontSize: 8),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildModelAction(AiCatalogModel model, bool isDownloaded, bool isDownloading, ModelDownloadInfo? downloadInfo) {
    if (isDownloading) {
      return GestureDetector(
        onTap: () => ref.read(modelCatalogProvider.notifier).cancelDownload(model.filename),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.redAccent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Icon(LucideIcons.x, size: 12, color: Colors.redAccent),
        ),
      );
    }

    if (isDownloaded) {
      if (model.category == ModelCategory.image) {
        return GestureDetector(
          onTap: () => _loadModelForImage(model),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.purpleAccent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.purpleAccent.withValues(alpha: 0.3)),
            ),
            child: Text('Load', style: GoogleFonts.inter(color: Colors.purpleAccent, fontSize: 9, fontWeight: FontWeight.bold)),
          ),
        );
      }

      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () => _loadModelForText(model),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.cyanAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.3)),
              ),
              child: Text('Load', style: GoogleFonts.inter(color: Colors.cyanAccent, fontSize: 9, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () => _showDeleteDialog(model),
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(LucideIcons.trash_2, size: 10, color: Colors.redAccent),
            ),
          ),
        ],
      );
    }

    return GestureDetector(
      onTap: () => ref.read(modelCatalogProvider.notifier).downloadModel(model),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.greenAccent.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.download, size: 10, color: Colors.greenAccent),
            const SizedBox(width: 4),
            Text('Download', style: GoogleFonts.inter(color: Colors.greenAccent, fontSize: 9, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Future<void> _loadModelForText(AiCatalogModel model) async {
    final notifier = ref.read(localAiServiceProvider.notifier);
    await notifier.selectModel(model.filename);
    if (!ref.read(localAiServiceProvider).isRunning) {
      await notifier.startServer();
    }
  }

  Future<void> _loadModelForImage(AiCatalogModel model) async {
    final catalogNotifier = ref.read(modelCatalogProvider.notifier);
    final modelsDir = await catalogNotifier.getModelsDir();
    if (modelsDir == null) return;
    final path = '$modelsDir/${model.filename}';
    await ref.read(imageGenProvider.notifier).loadModel(path, modelName: model.name);
  }

  void _showDeleteDialog(AiCatalogModel model) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2230),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete ${model.name}?', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text('This will free up ${model.size} of storage.', style: GoogleFonts.inter(color: Colors.white70, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.inter(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              ref.read(modelCatalogProvider.notifier).deleteModel(model.filename);
              Navigator.pop(ctx);
            },
            child: Text('Delete', style: GoogleFonts.inter(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsPanel(ChatSettings settings, AppLocalizations l10n) {
    return Expanded(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSettingSection('Generation', [
              _buildSliderSetting(
                'Temperature',
                settings.temperature,
                0.0,
                2.0,
                (v) => ref.read(chatSettingsProvider.notifier).setTemperature(v),
                '${settings.temperature.toStringAsFixed(2)}',
              ),
              _buildSliderSetting(
                'Max Tokens',
                settings.maxTokens.toDouble(),
                128,
                4096,
                (v) => ref.read(chatSettingsProvider.notifier).setMaxTokens(v.toInt()),
                '${settings.maxTokens}',
              ),
              _buildSliderSetting(
                'Context Size',
                settings.contextSize.toDouble(),
                512,
                8192,
                (v) => ref.read(chatSettingsProvider.notifier).setContextSize(v.toInt()),
                '${settings.contextSize}',
              ),
            ]),
            const SizedBox(height: 16),
            _buildSettingSection('System Prompt', [
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: TextField(
                  controller: TextEditingController(text: settings.systemPrompt),
                  style: GoogleFonts.inter(color: Colors.white70, fontSize: 11),
                  maxLines: 4,
                  minLines: 2,
                  decoration: InputDecoration(
                    hintText: 'System prompt...',
                    hintStyle: GoogleFonts.inter(color: Colors.white24, fontSize: 11),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(10),
                  ),
                  onSubmitted: (v) => ref.read(chatSettingsProvider.notifier).setSystemPrompt(v),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.inter(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }

  Widget _buildSliderSetting(String label, double value, double min, double max, ValueChanged<double> onChanged, String displayValue) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: GoogleFonts.inter(color: Colors.white70, fontSize: 11)),
              Text(displayValue, style: GoogleFonts.jetBrainsMono(color: Colors.cyanAccent, fontSize: 10)),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: Colors.cyanAccent,
              inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
              thumbColor: Colors.cyanAccent,
              overlayColor: Colors.cyanAccent.withValues(alpha: 0.1),
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
