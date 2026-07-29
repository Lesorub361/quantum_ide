import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:quantum_ide/features/plugins/presentation/notifiers/plugin_manager_notifier.dart';
import 'package:quantum_ide/features/plugins/presentation/widgets/plugin_card.dart';
import 'package:quantum_ide/shared/widgets/glass_container.dart';

class PluginManagerPage extends ConsumerStatefulWidget {
  const PluginManagerPage({super.key});

  @override
  ConsumerState<PluginManagerPage> createState() => _PluginManagerPageState();
}

class _PluginManagerPageState extends ConsumerState<PluginManagerPage> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pluginState = ref.watch(pluginManagerProvider);
    final pluginNotifier = ref.read(pluginManagerProvider.notifier);

    return Scaffold(
      backgroundColor: const Color(0xFF080A10),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(pluginState, pluginNotifier),
            _buildSearchBar(pluginNotifier),
            _buildTagFilter(pluginState, pluginNotifier),
            Expanded(child: _buildPluginList(pluginState, pluginNotifier)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
      PluginManagerState state, PluginManagerNotifier notifier) {
    return GlassContainer(
      blur: 20,
      opacity: 0.05,
      borderRadius: BorderRadius.zero,
      border:
          Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(LucideIcons.arrow_left, color: Colors.white70),
              onPressed: () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: 8),
            const Icon(LucideIcons.puzzle, size: 16, color: Colors.purpleAccent),
            const SizedBox(width: 8),
            Text(
              'Plugin Manager',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            Text(
              '${state.plugins.where((p) => p.status == PluginStatus.installed || p.status == PluginStatus.enabled).length} installed',
              style: GoogleFonts.inter(
                color: Colors.white38,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar(PluginManagerNotifier notifier) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: TextField(
        controller: _searchController,
        onChanged: (query) => notifier.setSearchQuery(query),
        decoration: InputDecoration(
          hintText: 'Search plugins...',
          hintStyle: GoogleFonts.inter(color: Colors.white24, fontSize: 12),
          filled: true,
          fillColor: Colors.black.withValues(alpha: 0.3),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide:
                BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide:
                BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide:
                const BorderSide(color: Colors.purpleAccent, width: 0.8),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          prefixIcon:
              const Icon(LucideIcons.search, size: 15, color: Colors.white38),
        ),
        style: GoogleFonts.inter(color: Colors.white, fontSize: 12),
      ),
    );
  }

  Widget _buildTagFilter(
      PluginManagerState state, PluginManagerNotifier notifier) {
    final tags = notifier.allTags;
    if (tags.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: tags.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == 0) {
            final isSelected = state.selectedTag == null;
            return FilterChip(
              label: Text(
                'All',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  color: isSelected ? Colors.white : Colors.white54,
                ),
              ),
              selected: isSelected,
              onSelected: (_) => notifier.setSelectedTag(null),
              backgroundColor: Colors.white.withValues(alpha: 0.04),
              selectedColor: Colors.purpleAccent.withValues(alpha: 0.2),
              side: BorderSide(
                color: isSelected
                    ? Colors.purpleAccent.withValues(alpha: 0.4)
                    : Colors.white.withValues(alpha: 0.06),
              ),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              visualDensity: VisualDensity.compact,
            );
          }

          final tag = tags[index - 1];
          final isSelected = state.selectedTag == tag;
          return FilterChip(
            label: Text(
              tag,
              style: GoogleFonts.inter(
                fontSize: 10,
                color: isSelected ? Colors.white : Colors.white54,
              ),
            ),
            selected: isSelected,
            onSelected: (_) =>
                notifier.setSelectedTag(isSelected ? null : tag),
            backgroundColor: Colors.white.withValues(alpha: 0.04),
            selectedColor: Colors.purpleAccent.withValues(alpha: 0.2),
            side: BorderSide(
              color: isSelected
                  ? Colors.purpleAccent.withValues(alpha: 0.4)
                  : Colors.white.withValues(alpha: 0.06),
            ),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            visualDensity: VisualDensity.compact,
          );
        },
      ),
    );
  }

  Widget _buildPluginList(
      PluginManagerState state, PluginManagerNotifier notifier) {
    if (state.isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.purpleAccent));
    }

    final plugins = state.filteredPlugins;

    if (plugins.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.puzzle,
                size: 48, color: Colors.white.withValues(alpha: 0.15)),
            const SizedBox(height: 16),
            Text(
              state.searchQuery.isEmpty ? 'No plugins found' : 'No matching plugins',
              style: GoogleFonts.inter(
                  color: Colors.white38, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      itemCount: plugins.length,
      itemBuilder: (context, index) {
        return PluginCard(
          plugin: plugins[index],
          onInstall: () => notifier.installPlugin(plugins[index].id),
          onUninstall: () => notifier.uninstallPlugin(plugins[index].id),
          onEnable: () => notifier.enablePlugin(plugins[index].id),
          onDisable: () => notifier.disablePlugin(plugins[index].id),
        );
      },
    );
  }
}
