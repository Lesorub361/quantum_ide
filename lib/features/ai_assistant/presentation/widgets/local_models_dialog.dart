import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quantum_ide/core/services/model_catalog_service.dart';
import 'package:quantum_ide/core/services/local_inference_service.dart';
import 'package:quantum_ide/core/services/chat_settings_service.dart';

/// Full-featured local models dialog.
/// Uses the SAME model catalogue as the sidebar (ModelCatalogNotifier) so both
/// panels always show and act on the same list and the same storage path.
class LocalModelsDialog extends ConsumerStatefulWidget {
  const LocalModelsDialog({super.key});

  @override
  ConsumerState<LocalModelsDialog> createState() => _LocalModelsDialogState();
}

class _LocalModelsDialogState extends ConsumerState<LocalModelsDialog> {
  ModelCategory _selectedCategory = ModelCategory.text;
  bool _showSettings = false;

  bool get _isMobilePlatform =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  Widget build(BuildContext context) {
    final catalogState = ref.watch(modelCatalogProvider);
    final inferenceState = ref.watch(localInferenceProvider);
    final inferenceNotifier = ref.read(localInferenceProvider.notifier);
    final catalogNotifier = ref.read(modelCatalogProvider.notifier);
    final chatSettings = ref.watch(chatSettingsProvider);

    final models = catalogState.models
        .where((m) => m.category == _selectedCategory)
        .toList();

    return Dialog(
      backgroundColor: const Color(0xFF16181D),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 620,
        height: 560,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ──────────────────────────────────────────────────
            Row(
              children: [
                ShaderMask(
                  shaderCallback: (b) => const LinearGradient(
                    colors: [Colors.cyanAccent, Colors.purpleAccent],
                  ).createShader(b),
                  child: const Icon(LucideIcons.cpu, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 10),
                Text(
                  _showSettings ? 'Local AI Settings' : 'Local AI Models',
                  style: GoogleFonts.inter(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                // Settings Toggle button
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
                        Icon(
                          _showSettings ? LucideIcons.arrow_left : LucideIcons.settings,
                          size: 12,
                          color: _showSettings ? Colors.cyanAccent : Colors.white54,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _showSettings ? 'Back' : 'Settings',
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
                const SizedBox(width: 8),
                // Platform badge
                if (!_isMobilePlatform && !_showSettings)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orangeAccent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(LucideIcons.monitor, size: 11, color: Colors.orangeAccent),
                        const SizedBox(width: 4),
                        Text(
                          'Desktop — use llama-server',
                          style: GoogleFonts.inter(fontSize: 10, color: Colors.orangeAccent),
                        ),
                      ],
                    ),
                  ),
                if (!_showSettings) const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(LucideIcons.x, color: Colors.white54),
                  onPressed: () => Navigator.of(context).pop(),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ],
            ),

            const SizedBox(height: 12),

            if (_showSettings)
              Expanded(
                child: _buildSettingsPanel(chatSettings),
              )
            else ...[
              // ── Loaded model + context bar ───────────────────────────────
              if (inferenceState.loadedModel != null)
                _buildLoadedModelBar(inferenceState, inferenceNotifier),

              // ── Platform warning (desktop) ───────────────────────────────
              if (!_isMobilePlatform) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orangeAccent.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.info, color: Colors.orangeAccent, size: 14),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Native inference (Run) works only on Android/iOS.\n'
                          'You can still download models here; they will be ready when you open the app on your phone.',
                          style: GoogleFonts.inter(color: Colors.orangeAccent, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // ── Error ────────────────────────────────────────────────────
              if (inferenceState.error != null)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(LucideIcons.triangle_alert, color: Colors.redAccent, size: 14),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        inferenceState.error!,
                        style: GoogleFonts.inter(color: Colors.redAccent, fontSize: 11),
                      ),
                    ),
                    // Reset crash flags so next load uses full settings context
                    TextButton.icon(
                      onPressed: () async {
                        await inferenceNotifier.resetModelLoadFlags();
                      },
                      icon: const Icon(LucideIcons.rotate_ccw, size: 11, color: Colors.orangeAccent),
                      label: Text(
                        'Сброс',
                        style: GoogleFonts.inter(
                          color: Colors.orangeAccent,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.x, size: 12, color: Colors.redAccent),
                      onPressed: () => inferenceNotifier.clearError(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 10),

            // ── Category Selector ────────────────────────────────────────
            _buildCategoryBar(),

            const SizedBox(height: 10),

            // ── Model List ───────────────────────────────────────────────
            Expanded(
              child: models.isEmpty
                  ? Center(
                      child: Text(
                        'No models in this category.',
                        style: GoogleFonts.inter(color: Colors.white38, fontSize: 13),
                      ),
                    )
                  : ListView.builder(
                      itemCount: models.length,
                      itemBuilder: (context, index) {
                        final model = models[index];
                        final isDownloaded = catalogState.downloadedModels[model.filename] == true;
                        final downloadInfo = catalogState.downloads[model.filename];
                        final isLoadedLocal =
                            inferenceState.loadedModel?.filename == model.filename;

                        return _buildModelCard(
                          model: model,
                          isDownloaded: isDownloaded,
                          downloadInfo: downloadInfo,
                          isLoaded: isLoadedLocal,
                          inferenceState: inferenceState,
                          inferenceNotifier: inferenceNotifier,
                          catalogNotifier: catalogNotifier,
                        );
                      },
                    ),
            ),
          ],
        ],
        ),
      ),
    );
  }

  // ── Loaded model status bar with context progress ─────────────────────────
  Widget _buildLoadedModelBar(
      LocalInferenceState inferenceState, LocalInferenceNotifier notifier) {
    final model = inferenceState.loadedModel!;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.cyanAccent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.circle_check, color: Colors.cyanAccent, size: 14),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${model.name} — loaded',
                  style: GoogleFonts.inter(
                    color: Colors.cyanAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Context token counter
              _buildContextBadge(inferenceState),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => notifier.unloadModel(),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Unload',
                    style: GoogleFonts.inter(
                        color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
          // Loading progress
          if (inferenceState.status == LocalModelStatus.loading) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: inferenceState.loadProgress < 0.01
                    ? null
                    : inferenceState.loadProgress,
                backgroundColor: Colors.white.withValues(alpha: 0.06),
                color: Colors.cyanAccent,
                minHeight: 3,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildContextBadge(LocalInferenceState state) {
    // Show token usage if engine exposes it (approximate: tokenCount / 4096)
    final used = state.tokenCount;
    const total = 4096; // default context window
    final ratio = (used / total).clamp(0.0, 1.0);
    final color = ratio < 0.6
        ? Colors.greenAccent
        : ratio < 0.85
            ? Colors.amberAccent
            : Colors.redAccent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.coins, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            '${(ratio * 100).toStringAsFixed(0)}% ctx',
            style: GoogleFonts.jetBrainsMono(fontSize: 10, color: color),
          ),
        ],
      ),
    );
  }

  // ── Category tabs ──────────────────────────────────────────────────────────
  Widget _buildCategoryBar() {
    return Row(
      children: [
        _categoryChip(ModelCategory.text, 'Text', LucideIcons.message_square),
        const SizedBox(width: 6),
        _categoryChip(ModelCategory.vision, 'Vision', LucideIcons.eye),
        const SizedBox(width: 6),
        _categoryChip(ModelCategory.image, 'Image', LucideIcons.image),
      ],
    );
  }

  Widget _categoryChip(ModelCategory cat, String label, IconData icon) {
    final isSelected = _selectedCategory == cat;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedCategory = cat),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: isSelected
                ? Colors.cyanAccent.withValues(alpha: 0.12)
                : Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? Colors.cyanAccent.withValues(alpha: 0.35)
                  : Colors.white.withValues(alpha: 0.06),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 12,
                  color: isSelected ? Colors.cyanAccent : Colors.white38),
              const SizedBox(width: 5),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: isSelected ? Colors.cyanAccent : Colors.white54,
                  fontWeight:
                      isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Single model card ──────────────────────────────────────────────────────
  Widget _buildModelCard({
    required AiCatalogModel model,
    required bool isDownloaded,
    required ModelDownloadInfo? downloadInfo,
    required bool isLoaded,
    required LocalInferenceState inferenceState,
    required LocalInferenceNotifier inferenceNotifier,
    required ModelCatalogNotifier catalogNotifier,
  }) {
    final isDownloading = downloadInfo?.status == DownloadStatus.downloading;
    final isPaused = downloadInfo?.status == DownloadStatus.paused;
    final runtimeLabel = model.runtime == ModelRuntime.litert
        ? 'LiteRT'
        : model.runtime == ModelRuntime.sd
            ? 'SD'
            : 'GGUF';
    final runtimeColor = model.runtime == ModelRuntime.litert
        ? Colors.greenAccent
        : model.runtime == ModelRuntime.sd
            ? Colors.purpleAccent
            : Colors.cyanAccent;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isLoaded
            ? Colors.cyanAccent.withValues(alpha: 0.05)
            : Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isLoaded
              ? Colors.cyanAccent.withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Runtime badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: runtimeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  runtimeLabel,
                  style: GoogleFonts.jetBrainsMono(
                      color: runtimeColor,
                      fontSize: 8,
                      fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      model.name,
                      style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${model.size} • ${model.description}',
                      style: GoogleFonts.inter(
                          fontSize: 10, color: Colors.white54),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Action button
              _buildAction(
                model: model,
                isDownloaded: isDownloaded,
                isDownloading: isDownloading,
                isPaused: isPaused,
                isLoaded: isLoaded,
                downloadInfo: downloadInfo,
                inferenceState: inferenceState,
                inferenceNotifier: inferenceNotifier,
                catalogNotifier: catalogNotifier,
              ),
            ],
          ),
          // Download progress bar
          if (isDownloading && downloadInfo != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: downloadInfo.progress,
                backgroundColor: Colors.white.withValues(alpha: 0.06),
                valueColor: AlwaysStoppedAnimation(runtimeColor),
                minHeight: 3,
              ),
            ),
            const SizedBox(height: 3),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${(downloadInfo.progress * 100).toStringAsFixed(1)}%'
                  ' • ${_fmt(downloadInfo.downloadedBytes)}'
                  ' / ${_fmt(downloadInfo.totalBytes)}',
                  style: GoogleFonts.jetBrainsMono(
                      color: Colors.white38, fontSize: 9),
                ),
                if (downloadInfo.speed > 0)
                  Text(
                    _fmtSpeed(downloadInfo.speed),
                    style: GoogleFonts.jetBrainsMono(
                        color: Colors.greenAccent, fontSize: 9),
                  ),
              ],
            ),
          ],
          // Paused state
          if (isPaused) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(LucideIcons.pause,
                    size: 11, color: Colors.amberAccent),
                const SizedBox(width: 4),
                Text(
                  'Download paused — tap Resume to continue',
                  style: GoogleFonts.inter(
                      color: Colors.amberAccent, fontSize: 10),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAction({
    required AiCatalogModel model,
    required bool isDownloaded,
    required bool isDownloading,
    required bool isPaused,
    required bool isLoaded,
    required ModelDownloadInfo? downloadInfo,
    required LocalInferenceState inferenceState,
    required LocalInferenceNotifier inferenceNotifier,
    required ModelCatalogNotifier catalogNotifier,
  }) {
    // Currently downloading → Pause
    if (isDownloading) {
      return _actionBtn(
        label: 'Pause',
        icon: LucideIcons.pause,
        color: Colors.amberAccent,
        onTap: () => ref.read(modelCatalogProvider.notifier).cancelDownload(model.filename),
      );
    }

    // Paused → Resume
    if (isPaused) {
      return _actionBtn(
        label: 'Resume',
        icon: LucideIcons.play,
        color: Colors.amberAccent,
        onTap: () => ref.read(modelCatalogProvider.notifier).downloadModel(model),
      );
    }

    // Already loaded in inference engine → show badge only
    if (isLoaded) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.cyanAccent.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          'Active',
          style: GoogleFonts.inter(
              color: Colors.cyanAccent,
              fontSize: 10,
              fontWeight: FontWeight.bold),
        ),
      );
    }

    // Loading in progress for this model
    if (inferenceState.status == LocalModelStatus.loading &&
        inferenceState.loadedModel?.filename == model.filename) {
      return SizedBox(
        width: 60,
        child: Column(
          children: [
            LinearProgressIndicator(
              value: inferenceState.loadProgress < 0.01
                  ? null
                  : inferenceState.loadProgress,
              color: Colors.cyanAccent,
              backgroundColor: Colors.white10,
            ),
            const SizedBox(height: 2),
            Text(
              '${(inferenceState.loadProgress * 100).toStringAsFixed(0)}%',
              style: GoogleFonts.jetBrainsMono(
                  fontSize: 9, color: Colors.white54),
            ),
          ],
        ),
      );
    }

    // Downloaded but not loaded → Run / Delete
    if (isDownloaded) {
      // Image models: no native inference — just show "Ready" tag
      if (model.category == ModelCategory.image) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.purpleAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('Ready',
                  style: GoogleFonts.inter(
                      color: Colors.purpleAccent,
                      fontSize: 10,
                      fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 4),
            _deleteBtn(model, catalogNotifier),
          ],
        );
      }

      // Text / Vision models
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _actionBtn(
            label: 'Run',
            icon: LucideIcons.play,
            color: Colors.cyanAccent,
            onTap: _isMobilePlatform
                ? () {
                    // Convert AiCatalogModel → LocalModelInfo
                    final localModel = LocalModelInfo(
                      name: model.name,
                      filename: model.filename,
                      url: model.url,
                      size: model.size,
                      description: model.description,
                      template: model.template,
                      isVision: model.isVision,
                    );
                    inferenceNotifier.loadModel(localModel);
                  }
                : null, // disabled on desktop
          ),
          const SizedBox(width: 4),
          _deleteBtn(model, catalogNotifier),
        ],
      );
    }

    // Not downloaded → Download
    return _actionBtn(
      label: 'Download',
      icon: LucideIcons.download,
      color: Colors.greenAccent,
      onTap: () => ref.read(modelCatalogProvider.notifier).downloadModel(model),
    );
  }

  Widget _actionBtn({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback? onTap,
  }) {
    final disabled = onTap == null;
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: disabled ? 0.4 : 1.0,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 11, color: color),
              const SizedBox(width: 4),
              Text(label,
                  style: GoogleFonts.inter(
                      color: color, fontSize: 10, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _deleteBtn(AiCatalogModel model, ModelCatalogNotifier notifier) {
    return GestureDetector(
      onTap: () => _confirmDelete(model, notifier),
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Icon(LucideIcons.trash_2, size: 11, color: Colors.redAccent),
      ),
    );
  }

  void _confirmDelete(AiCatalogModel model, ModelCatalogNotifier notifier) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2230),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text('Delete ${model.name}?',
            style: GoogleFonts.inter(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
        content: Text(
          'This will free up ${model.size} of storage.',
          style: GoogleFonts.inter(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: GoogleFonts.inter(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              notifier.deleteModel(model.filename);
              Navigator.pop(ctx);
            },
            child: Text('Delete',
                style: GoogleFonts.inter(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  // ── Formatting helpers ─────────────────────────────────────────────────────
  String _fmt(int bytes) => ModelCatalogNotifier.formatBytes(bytes);
  String _fmtSpeed(double bps) => ModelCatalogNotifier.formatSpeed(bps);

  // ── Settings widgets ───────────────────────────────────────────────────────
  Widget _buildSettingsPanel(ChatSettings settings) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSettingSection('Generation Parameters', [
            _buildSliderSetting(
              'Temperature',
              settings.temperature,
              0.0,
              2.0,
              (v) => ref.read(chatSettingsProvider.notifier).setTemperature(v),
              settings.temperature.toStringAsFixed(2),
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
              32768,
              (v) => ref.read(chatSettingsProvider.notifier).setContextSize(v.toInt()),
              '${settings.contextSize}',
            ),
          ]),
          const SizedBox(height: 16),
          _buildSettingSection('Local AI Performance (LiteRT)', [
            const SizedBox(height: 4),
            Row(
              children: [
                _performanceModeChip('auto_fast', 'Auto', LucideIcons.sparkles, settings.liteRtPerformanceMode),
                const SizedBox(width: 6),
                _performanceModeChip('gpu_fast', 'GPU', LucideIcons.zap, settings.liteRtPerformanceMode),
                const SizedBox(width: 6),
                _performanceModeChip('cpu_safe', 'CPU Only', LucideIcons.shield, settings.liteRtPerformanceMode),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              settings.liteRtPerformanceMode == 'auto_fast'
                  ? 'Tries GPU acceleration first, falls back to CPU if it fails.'
                  : settings.liteRtPerformanceMode == 'gpu_fast'
                      ? 'Forces GPU acceleration. Maximum speed, but may crash on devices with low VRAM.'
                      : 'Forces CPU mode. Stable execution with lower speed.',
              style: GoogleFonts.inter(color: Colors.white38, fontSize: 10),
            ),
          ]),
          const SizedBox(height: 16),
          _buildSettingSection('Image Generation (Stable Diffusion)', [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Image Backend',
                  style: GoogleFonts.inter(color: Colors.white70, fontSize: 11),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _backendModeChip(true, 'GPU', settings.imageGenForceCpu),
                    const SizedBox(width: 4),
                    _backendModeChip(false, 'CPU', settings.imageGenForceCpu),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            _buildSliderSetting(
              'GPU Safety Threshold',
              settings.imageGenGpuGuardMb.toDouble(),
              0,
              4096,
              (v) => ref.read(chatSettingsProvider.notifier).setImageGenGpuGuardMb(v.toInt()),
              settings.imageGenGpuGuardMb <= 0 ? 'Off' : '${settings.imageGenGpuGuardMb} MB',
            ),
            Text(
              'Models at or above this size use CPU to prevent out-of-memory crashes on GPU.',
              style: GoogleFonts.inter(color: Colors.white38, fontSize: 10),
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
    );
  }

  Widget _buildSettingSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.inter(color: Colors.white54, fontSize: 10.5, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }

  Widget _buildSliderSetting(String label, double value, double min, double max, ValueChanged<double> onChanged, String displayValue) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: GoogleFonts.inter(color: Colors.white70, fontSize: 11)),
              Text(displayValue, style: GoogleFonts.jetBrainsMono(color: Colors.cyanAccent, fontSize: 10, fontWeight: FontWeight.bold)),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: Colors.cyanAccent,
              inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
              thumbColor: Colors.cyanAccent,
              overlayColor: Colors.cyanAccent.withValues(alpha: 0.1),
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
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

  Widget _performanceModeChip(String value, String label, IconData icon, String current) {
    final isSelected = value == current;
    final color = isSelected ? Colors.cyanAccent : Colors.white38;
    return Expanded(
      child: GestureDetector(
        onTap: () => ref.read(chatSettingsProvider.notifier).setLiteRtPerformanceMode(value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: isSelected ? Colors.cyanAccent.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isSelected ? Colors.cyanAccent.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.05),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 11, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 10.5,
                  color: isSelected ? Colors.white : Colors.white54,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _backendModeChip(bool forGpu, String label, bool forceCpu) {
    final isSelected = forGpu ? !forceCpu : forceCpu;
    return GestureDetector(
      onTap: () => ref.read(chatSettingsProvider.notifier).setImageGenForceCpu(!forGpu),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? Colors.purpleAccent.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? Colors.purpleAccent.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.05),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 10.5,
            color: isSelected ? Colors.white : Colors.white54,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
