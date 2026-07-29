import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quantum_ide/core/services/local_inference_service.dart';
import 'package:quantum_ide/l10n/app_localizations.dart';

class LocalModelsPage extends ConsumerStatefulWidget {
  const LocalModelsPage({super.key});

  @override
  ConsumerState<LocalModelsPage> createState() => _LocalModelsPageState();
}

class _LocalModelsPageState extends ConsumerState<LocalModelsPage> {
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(localInferenceProvider);
    final l10n = AppLocalizations.of(context)!;
    final isMobile = MediaQuery.of(context).size.width < 800;

    return Scaffold(
      backgroundColor: const Color(0xFF080A10),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0F14),
        title: Row(
          children: [
            const Icon(LucideIcons.cpu, color: Colors.cyanAccent, size: 20),
            const SizedBox(width: 8),
            Text(
              l10n.localModels,
              style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          if (state.loadedModel != null)
            Container(
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.greenAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.greenAccent,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    state.loadedModel!.name,
                    style: GoogleFonts.inter(color: Colors.greenAccent, fontSize: 12),
                  ),
                ],
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          _buildFilterBar(l10n),
          if (state.error != null) _buildErrorBanner(state),
          Expanded(child: _buildModelList(state, l10n, isMobile)),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(LocalInferenceState state) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(LucideIcons.triangle_alert, color: Colors.redAccent, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: SelectableText(
              state.error!,
              style: GoogleFonts.inter(color: Colors.redAccent, fontSize: 13),
            ),
          ),
          IconButton(
            icon: const Icon(LucideIcons.x, size: 16, color: Colors.redAccent),
            onPressed: () => ref.read(localInferenceProvider.notifier).clearError(),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0F14),
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
      ),
      child: Row(
        children: [
          _buildFilterChip('all', l10n.all, LucideIcons.layers),
          const SizedBox(width: 8),
          _buildFilterChip('downloaded', l10n.downloaded, LucideIcons.download),
          const SizedBox(width: 8),
          _buildFilterChip('vision', l10n.vision, LucideIcons.eye),
          const SizedBox(width: 8),
          _buildFilterChip('uncensored', l10n.uncensored, LucideIcons.lock),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String value, String label, IconData icon) {
    final isSelected = _filter == value;
    return FilterChip(
      selected: isSelected,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: isSelected ? Colors.cyanAccent : Colors.white54),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.white54)),
        ],
      ),
      onSelected: (_) => setState(() => _filter = value),
      backgroundColor: Colors.white.withValues(alpha: 0.05),
      selectedColor: Colors.cyanAccent.withValues(alpha: 0.2),
      checkmarkColor: Colors.cyanAccent,
      side: BorderSide(
        color: isSelected ? Colors.cyanAccent.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.1),
      ),
    );
  }

  Widget _buildModelList(LocalInferenceState state, AppLocalizations l10n, bool isMobile) {
    final models = state.availableModels.where((model) {
      switch (_filter) {
        case 'downloaded':
          return isDownloaded(model.filename);
        case 'vision':
          return model.isVision;
        case 'uncensored':
          return model.name.toLowerCase().contains('uncensored') || 
                 model.name.toLowerCase().contains('abliterated') ||
                 model.name.toLowerCase().contains('dolphin');
        default:
          return true;
      }
    }).toList();

    if (models.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.package_search, size: 64, color: Colors.white.withValues(alpha: 0.1)),
            const SizedBox(height: 16),
            Text(
              l10n.noModelsFound,
              style: GoogleFonts.inter(color: Colors.white38, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: models.length,
      itemBuilder: (context, index) => _buildModelCard(models[index], state, l10n, isMobile),
    );
  }

  Widget _buildModelCard(LocalModelInfo model, LocalInferenceState state, AppLocalizations l10n, bool isMobile) {
    final downloaded = isDownloaded(model.filename);
    final isActive = state.loadedModel?.filename == model.filename;
    final downloadProgress = state.activeDownloads[model.filename];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isActive 
            ? Colors.greenAccent.withValues(alpha: 0.1)
            : Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive 
              ? Colors.greenAccent.withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _getModelColor(model).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(_getModelIcon(model), size: 20, color: _getModelColor(model)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        model.name,
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        model.size,
                        style: GoogleFonts.jetBrainsMono(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                if (model.isVision)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.purpleAccent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'VISION',
                      style: GoogleFonts.inter(color: Colors.purpleAccent, fontSize: 8, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              model.description,
              style: GoogleFonts.inter(color: Colors.white60, fontSize: 12),
            ),
            const SizedBox(height: 12),
            if (downloadProgress != null)
              _buildDownloadProgress(downloadProgress)
            else if (downloaded)
              _buildDownloadedActions(model, isActive, l10n)
            else
              _buildDownloadButton(model, l10n),
          ],
        ),
      ),
    );
  }

  Widget _buildDownloadProgress(DownloadProgress progress) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${(progress.progress * 100).toStringAsFixed(1)}%',
              style: GoogleFonts.jetBrainsMono(color: Colors.cyanAccent, fontSize: 12),
            ),
            Text(
              '${(progress.downloadedBytes / 1024 / 1024).toStringAsFixed(0)} / ${(progress.totalBytes / 1024 / 1024).toStringAsFixed(0)} MB',
              style: GoogleFonts.jetBrainsMono(color: Colors.white54, fontSize: 11),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: progress.progress,
          backgroundColor: Colors.white.withValues(alpha: 0.1),
          valueColor: const AlwaysStoppedAnimation<Color>(Colors.cyanAccent),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${(progress.bytesPerSecond / 1024 / 1024).toStringAsFixed(1)} MB/s',
              style: GoogleFonts.jetBrainsMono(color: Colors.white38, fontSize: 10),
            ),
            if (progress.eta != null)
              Text(
                'ETA: ${progress.eta!.inMinutes}:${(progress.eta!.inSeconds % 60).toString().padLeft(2, '0')}',
                style: GoogleFonts.jetBrainsMono(color: Colors.white38, fontSize: 10),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildDownloadedActions(LocalModelInfo model, bool isActive, AppLocalizations l10n) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => _loadModel(model),
            icon: Icon(isActive ? LucideIcons.square : LucideIcons.play, size: 14),
            label: Text(isActive ? l10n.unload : l10n.load),
            style: ElevatedButton.styleFrom(
              backgroundColor: isActive 
                  ? Colors.orangeAccent.withValues(alpha: 0.15)
                  : Colors.greenAccent.withValues(alpha: 0.15),
              foregroundColor: isActive ? Colors.orangeAccent : Colors.greenAccent,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: () => _deleteModel(model),
          icon: const Icon(LucideIcons.trash_2, size: 16),
          color: Colors.redAccent,
          tooltip: l10n.delete,
        ),
      ],
    );
  }

  Widget _buildDownloadButton(LocalModelInfo model, AppLocalizations l10n) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () => _downloadModel(model),
        icon: const Icon(LucideIcons.download, size: 14),
        label: Text('${l10n.download} (${model.size})'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.cyanAccent.withValues(alpha: 0.15),
          foregroundColor: Colors.cyanAccent,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }

  Color _getModelColor(LocalModelInfo model) {
    if (model.isVision) return Colors.purpleAccent;
    if (model.name.toLowerCase().contains('qwen')) return Colors.cyanAccent;
    if (model.name.toLowerCase().contains('llama')) return Colors.orangeAccent;
    if (model.name.toLowerCase().contains('phi')) return Colors.blueAccent;
    if (model.name.toLowerCase().contains('gemma')) return Colors.greenAccent;
    return Colors.white;
  }

  IconData _getModelIcon(LocalModelInfo model) {
    if (model.isVision) return LucideIcons.eye;
    if (model.name.toLowerCase().contains('qwen')) return LucideIcons.brain;
    if (model.name.toLowerCase().contains('llama')) return LucideIcons.bot;
    if (model.name.toLowerCase().contains('phi')) return LucideIcons.microchip;
    if (model.name.toLowerCase().contains('gemma')) return LucideIcons.diamond;
    return LucideIcons.cpu;
  }

  bool isDownloaded(String filename) {
    final state = ref.read(localInferenceProvider);
    return state.downloadedFiles.contains(filename);
  }

  void _downloadModel(LocalModelInfo model) {
    ref.read(localInferenceProvider.notifier).downloadModel(model);
  }

  void _loadModel(LocalModelInfo model) {
    final state = ref.read(localInferenceProvider);
    if (state.loadedModel?.filename == model.filename) {
      ref.read(localInferenceProvider.notifier).unloadModel();
    } else {
      ref.read(localInferenceProvider.notifier).loadModel(model);
    }
  }

  void _deleteModel(LocalModelInfo model) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E2230),
        title: Text(AppLocalizations.of(context)!.confirmDelete, style: const TextStyle(color: Colors.white)),
        content: Text(
          AppLocalizations.of(context)!.areYouSureDelete(model.name),
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context)!.cancel, style: const TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(localInferenceProvider.notifier).deleteModel(model.filename);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: Text(AppLocalizations.of(context)!.delete, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
