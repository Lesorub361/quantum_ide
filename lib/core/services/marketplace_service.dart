import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';

class MarketplaceItem {
  final String id;
  final String name;
  final String description;
  final String version;
  final String author;
  final MarketplaceItemType type;
  final String? thumbnailUrl;
  final List<String> tags;
  final int downloads;
  final double rating;
  final bool isInstalled;
  final bool isEnabled;

  MarketplaceItem({
    required this.id,
    required this.name,
    required this.description,
    required this.version,
    required this.author,
    required this.type,
    this.thumbnailUrl,
    this.tags = const [],
    this.downloads = 0,
    this.rating = 0.0,
    this.isInstalled = false,
    this.isEnabled = true,
  });

  MarketplaceItem copyWith({
    String? name,
    String? description,
    String? version,
    String? author,
    String? thumbnailUrl,
    List<String>? tags,
    int? downloads,
    double? rating,
    bool? isInstalled,
    bool? isEnabled,
  }) {
    return MarketplaceItem(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      version: version ?? this.version,
      author: author ?? this.author,
      type: type,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      tags: tags ?? this.tags,
      downloads: downloads ?? this.downloads,
      rating: rating ?? this.rating,
      isInstalled: isInstalled ?? this.isInstalled,
      isEnabled: isEnabled ?? this.isEnabled,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'version': version,
    'author': author,
    'type': type.name,
    'thumbnailUrl': thumbnailUrl,
    'tags': tags,
    'downloads': downloads,
    'rating': rating,
    'isInstalled': isInstalled,
    'isEnabled': isEnabled,
  };

  factory MarketplaceItem.fromJson(Map<String, dynamic> json) => MarketplaceItem(
    id: json['id'] ?? '',
    name: json['name'] ?? '',
    description: json['description'] ?? '',
    version: json['version'] ?? '1.0.0',
    author: json['author'] ?? '',
    type: MarketplaceItemType.values.firstWhere(
      (e) => e.name == json['type'],
      orElse: () => MarketplaceItemType.plugin,
    ),
    thumbnailUrl: json['thumbnailUrl'],
    tags: (json['tags'] as List?)?.cast<String>() ?? [],
    downloads: json['downloads'] ?? 0,
    rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
    isInstalled: json['isInstalled'] ?? false,
    isEnabled: json['isEnabled'] ?? true,
  );
}

enum MarketplaceItemType { plugin, theme }

class MarketplaceState {
  final List<MarketplaceItem> availableItems;
  final List<MarketplaceItem> installedItems;
  final bool isLoading;
  final String? error;
  final String searchQuery;

  MarketplaceState({
    this.availableItems = const [],
    this.installedItems = const [],
    this.isLoading = false,
    this.error,
    this.searchQuery = '',
  });

  MarketplaceState copyWith({
    List<MarketplaceItem>? availableItems,
    List<MarketplaceItem>? installedItems,
    bool? isLoading,
    String? error,
    String? searchQuery,
  }) {
    return MarketplaceState(
      availableItems: availableItems ?? this.availableItems,
      installedItems: installedItems ?? this.installedItems,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }
}

class MarketplaceService extends StateNotifier<MarketplaceState> {
  final Ref ref;
  final Dio _dio = Dio();
  late final String _storageDir;

  static const _mockRegistryUrl = 'https://registry.quantum-ide.dev/api/v1';

  MarketplaceService(this.ref) : super(MarketplaceState()) {
    _initStorage();
  }

  Future<void> _initStorage() async {
    final dir = await getApplicationDocumentsDirectory();
    _storageDir = p.join(dir.path, 'quantum_ide', 'marketplace');
    await Directory(_storageDir).create(recursive: true);
    await _loadInstalledItems();
  }

  String get _installedConfigPath => p.join(_storageDir, 'installed.json');

  Future<void> _loadInstalledItems() async {
    try {
      final file = File(_installedConfigPath);
      if (await file.exists()) {
        final json = await file.readAsString();
        final parsed = (jsonDecode(json) as List).map((e) => MarketplaceItem.fromJson(e)).toList();
        state = state.copyWith(installedItems: parsed);
      }
    } catch (_) {}
  }

  Future<void> _saveInstalledItems() async {
    final file = File(_installedConfigPath);
    final json = state.installedItems.map((e) => e.toJson()).toList();
    await file.writeAsString(jsonEncode(json));
  }

  Future<void> search(String query) async {
    if (query.isEmpty) {
      state = state.copyWith(availableItems: [], searchQuery: '');
      return;
    }
    state = state.copyWith(isLoading: true, searchQuery: query, error: null);
    try {
      final response = await _dio.get(
        '$_mockRegistryUrl/search',
        queryParameters: {'q': query, 'limit': 30},
      );
      final items = (response.data['items'] as List)
          .map((e) => MarketplaceItem.fromJson(e))
          .toList();
      state = state.copyWith(availableItems: items, isLoading: false);
    } catch (e) {
      state = state.copyWith(
        availableItems: _getMockItems(query),
        isLoading: false,
        error: 'Using offline data: $e',
      );
    }
  }

  List<MarketplaceItem> _getMockItems(String query) {
    return [
      MarketplaceItem(
        id: 'theme-quantum-dark',
        name: 'Quantum Dark Theme',
        description: 'Default dark theme with quantum-inspired accent colors',
        version: '2.1.0',
        author: 'QuantumTeam',
        type: MarketplaceItemType.theme,
        tags: ['dark', 'modern'],
        downloads: 15420,
        rating: 4.8,
        isInstalled: state.installedItems.any((i) => i.id == 'theme-quantum-dark'),
      ),
      MarketplaceItem(
        id: 'plugin-git-extended',
        name: 'Git Extended',
        description: 'Advanced git operations with visual diff and merge tools',
        version: '1.3.2',
        author: 'DevTools',
        type: MarketplaceItemType.plugin,
        tags: ['git', 'productivity'],
        downloads: 28300,
        rating: 4.6,
        isInstalled: state.installedItems.any((i) => i.id == 'plugin-git-extended'),
      ),
      MarketplaceItem(
        id: 'plugin-docker',
        name: 'Docker Manager',
        description: 'Manage Docker containers and images from the IDE',
        version: '1.0.0',
        author: 'CloudTools',
        type: MarketplaceItemType.plugin,
        tags: ['docker', 'containers'],
        downloads: 9800,
        rating: 4.3,
        isInstalled: state.installedItems.any((i) => i.id == 'plugin-docker'),
      ),
    ].where((i) => i.name.toLowerCase().contains(query.toLowerCase()) ||
        i.tags.any((t) => t.contains(query.toLowerCase()))).toList();
  }

  Future<bool> installItem(MarketplaceItem item) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _dio.download(
        '$_mockRegistryUrl/download/${item.id}',
        p.join(_storageDir, '${item.id}.zip'),
      );
    } catch (_) {}

    final installedItem = item.copyWith(isInstalled: true, isEnabled: true);
    final updatedInstalled = [...state.installedItems, installedItem];
    final updatedAvailable = state.availableItems.map((i) =>
        i.id == item.id ? installedItem : i).toList();

    state = state.copyWith(
      installedItems: updatedInstalled,
      availableItems: updatedAvailable,
      isLoading: false,
    );
    await _saveInstalledItems();
    return true;
  }

  Future<bool> uninstallItem(String itemId) async {
    final updatedInstalled = state.installedItems.where((i) => i.id != itemId).toList();
    final updatedAvailable = state.availableItems.map((i) =>
        i.id == itemId ? i.copyWith(isInstalled: false) : i).toList();

    final itemFile = File(p.join(_storageDir, '$itemId.zip'));
    if (await itemFile.exists()) await itemFile.delete();

    state = state.copyWith(
      installedItems: updatedInstalled,
      availableItems: updatedAvailable,
    );
    await _saveInstalledItems();
    return true;
  }

  Future<void> toggleItem(String itemId) async {
    final updatedInstalled = state.installedItems.map((i) =>
        i.id == itemId ? i.copyWith(isEnabled: !i.isEnabled) : i).toList();
    state = state.copyWith(installedItems: updatedInstalled);
    await _saveInstalledItems();
  }

  List<MarketplaceItem> get installedPlugins =>
      state.installedItems.where((i) => i.type == MarketplaceItemType.plugin).toList();

  List<MarketplaceItem> get installedThemes =>
      state.installedItems.where((i) => i.type == MarketplaceItemType.theme).toList();
}

final marketplaceServiceProvider = StateNotifierProvider<MarketplaceService, MarketplaceState>((ref) {
  return MarketplaceService(ref);
});
