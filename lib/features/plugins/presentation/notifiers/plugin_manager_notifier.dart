import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

enum PluginStatus { available, installed, enabled, disabled }

class Plugin {
  final String id;
  final String name;
  final String description;
  final String version;
  final String author;
  final String iconPath;
  final PluginStatus status;
  final List<String> tags;
  final double rating;
  final int downloads;

  Plugin({
    required this.id,
    required this.name,
    required this.description,
    required this.version,
    required this.author,
    this.iconPath = '',
    this.status = PluginStatus.available,
    this.tags = const [],
    this.rating = 0.0,
    this.downloads = 0,
  });

  Plugin copyWith({
    PluginStatus? status,
  }) {
    return Plugin(
      id: id,
      name: name,
      description: description,
      version: version,
      author: author,
      iconPath: iconPath,
      status: status ?? this.status,
      tags: tags,
      rating: rating,
      downloads: downloads,
    );
  }
}

class PluginManagerState {
  final List<Plugin> plugins;
  final String searchQuery;
  final String? selectedTag;
  final bool isLoading;
  final String? error;

  PluginManagerState({
    this.plugins = const [],
    this.searchQuery = '',
    this.selectedTag,
    this.isLoading = false,
    this.error,
  });

  PluginManagerState copyWith({
    List<Plugin>? plugins,
    String? searchQuery,
    String? selectedTag,
    bool? isLoading,
    String? error,
  }) {
    return PluginManagerState(
      plugins: plugins ?? this.plugins,
      searchQuery: searchQuery ?? this.searchQuery,
      selectedTag: selectedTag,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }

  List<Plugin> get filteredPlugins {
    return plugins.where((plugin) {
      final matchesSearch = searchQuery.isEmpty ||
          plugin.name.toLowerCase().contains(searchQuery.toLowerCase()) ||
          plugin.description.toLowerCase().contains(searchQuery.toLowerCase());
      final matchesTag = selectedTag == null || plugin.tags.contains(selectedTag);
      return matchesSearch && matchesTag;
    }).toList();
  }
}

class PluginManagerNotifier extends StateNotifier<PluginManagerState> {
  final _uuid = const Uuid();

  PluginManagerNotifier() : super(PluginManagerState()) {
    _loadMockPlugins();
  }

  void _loadMockPlugins() {
    final mockPlugins = [
      Plugin(
        id: _uuid.v4(),
        name: 'Python Support',
        description: 'Full Python language support with LSP, debugging, and virtual environments',
        version: '2.1.0',
        author: 'QuantumIDE',
        status: PluginStatus.installed,
        tags: ['language', 'python'],
        rating: 4.8,
        downloads: 12400,
      ),
      Plugin(
        id: _uuid.v4(),
        name: 'Docker Support',
        description: 'Docker Compose syntax highlighting and container management',
        version: '1.3.2',
        author: 'QuantumIDE',
        status: PluginStatus.available,
        tags: ['devops', 'docker'],
        rating: 4.5,
        downloads: 8200,
      ),
      Plugin(
        id: _uuid.v4(),
        name: 'Tailwind CSS',
        description: 'Tailwind CSS IntelliSense, class completion, and preview',
        version: '1.8.0',
        author: 'QuantumIDE',
        status: PluginStatus.available,
        tags: ['css', 'tailwind'],
        rating: 4.9,
        downloads: 21000,
      ),
      Plugin(
        id: _uuid.v4(),
        name: 'Git Lens',
        description: 'Enhanced Git integration with blame annotations and history',
        version: '3.0.1',
        author: 'Community',
        status: PluginStatus.available,
        tags: ['git', 'productivity'],
        rating: 4.7,
        downloads: 15600,
      ),
      Plugin(
        id: _uuid.v4(),
        name: 'ESLint Integration',
        description: 'Real-time linting for JavaScript and TypeScript projects',
        version: '2.5.0',
        author: 'Community',
        status: PluginStatus.disabled,
        tags: ['linting', 'javascript'],
        rating: 4.6,
        downloads: 19800,
      ),
    ];
    state = state.copyWith(plugins: mockPlugins);
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  void setSelectedTag(String? tag) {
    state = state.copyWith(selectedTag: tag);
  }

  Future<void> installPlugin(String pluginId) async {
    state = state.copyWith(isLoading: true);
    try {
      await Future.delayed(const Duration(seconds: 1));
      final updatedPlugins = state.plugins.map((p) {
        if (p.id == pluginId) {
          return p.copyWith(status: PluginStatus.installed);
        }
        return p;
      }).toList();
      state = state.copyWith(plugins: updatedPlugins, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> uninstallPlugin(String pluginId) async {
    state = state.copyWith(isLoading: true);
    try {
      await Future.delayed(const Duration(milliseconds: 500));
      final updatedPlugins = state.plugins.map((p) {
        if (p.id == pluginId) {
          return p.copyWith(status: PluginStatus.available);
        }
        return p;
      }).toList();
      state = state.copyWith(plugins: updatedPlugins, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> enablePlugin(String pluginId) async {
    final updatedPlugins = state.plugins.map((p) {
      if (p.id == pluginId && p.status == PluginStatus.disabled) {
        return p.copyWith(status: PluginStatus.enabled);
      }
      return p;
    }).toList();
    state = state.copyWith(plugins: updatedPlugins);
  }

  Future<void> disablePlugin(String pluginId) async {
    final updatedPlugins = state.plugins.map((p) {
      if (p.id == pluginId &&
          (p.status == PluginStatus.installed || p.status == PluginStatus.enabled)) {
        return p.copyWith(status: PluginStatus.disabled);
      }
      return p;
    }).toList();
    state = state.copyWith(plugins: updatedPlugins);
  }

  List<String> get allTags {
    final tags = <String>{};
    for (final plugin in state.plugins) {
      tags.addAll(plugin.tags);
    }
    return tags.toList()..sort();
  }
}

final pluginManagerProvider =
    StateNotifierProvider<PluginManagerNotifier, PluginManagerState>((ref) {
  return PluginManagerNotifier();
});
