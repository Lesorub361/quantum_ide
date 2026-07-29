import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quantum_ide/core/services/api_client_service.dart';

class ApiClientPage extends ConsumerStatefulWidget {
  const ApiClientPage({super.key});

  @override
  ConsumerState<ApiClientPage> createState() => _ApiClientPageState();
}

class _ApiClientPageState extends ConsumerState<ApiClientPage> with SingleTickerProviderStateMixin {
  final _urlController = TextEditingController();
  final _bodyController = TextEditingController();
  final _headerKeyController = TextEditingController();
  final _headerValueController = TextEditingController();
  final _collectionNameController = TextEditingController();
  final _envKeyController = TextEditingController();
  final _envValueController = TextEditingController();
  String _selectedMethod = 'GET';
  final Map<String, String> _headers = {'Content-Type': 'application/json'};
  late TabController _tabController;
  late TabController _sideTabController;
  bool _showSidebar = true;
  final _methods = ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _sideTabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _bodyController.dispose();
    _headerKeyController.dispose();
    _headerValueController.dispose();
    _collectionNameController.dispose();
    _envKeyController.dispose();
    _envValueController.dispose();
    _tabController.dispose();
    _sideTabController.dispose();
    super.dispose();
  }

  Future<void> _sendRequest() async {
    if (_urlController.text.isEmpty) return;

    final request = ApiRequest(
      method: _selectedMethod,
      url: _urlController.text,
      headers: Map.from(_headers),
      body: _bodyController.text.isNotEmpty ? _bodyController.text : null,
    );

    await ref.read(apiClientProvider.notifier).sendRequest(request);
  }

  void _addHeader() {
    if (_headerKeyController.text.isNotEmpty) {
      setState(() {
        _headers[_headerKeyController.text] = _headerValueController.text;
        _headerKeyController.clear();
        _headerValueController.clear();
      });
    }
  }

  void _showCreateCollectionDialog() {
    _collectionNameController.clear();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Collection'),
        content: TextField(
          controller: _collectionNameController,
          decoration: const InputDecoration(hintText: 'Collection name', isDense: true),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (_collectionNameController.text.isNotEmpty) {
                ref.read(apiClientProvider.notifier).createCollection(_collectionNameController.text.trim());
                Navigator.pop(context);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showEnvVarsDialog() {
    _envKeyController.clear();
    _envValueController.clear();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Environment Variables'),
        content: SizedBox(
          width: 350,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _envKeyController,
                      decoration: const InputDecoration(hintText: 'Variable name', isDense: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _envValueController,
                      decoration: const InputDecoration(hintText: 'Value', isDense: true),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      if (_envKeyController.text.isNotEmpty) {
                        ref.read(apiClientProvider.notifier).setEnvironmentVariable(
                          _envKeyController.text.trim(),
                          _envValueController.text.trim(),
                        );
                        _envKeyController.clear();
                        _envValueController.clear();
                      }
                    },
                    icon: const Icon(LucideIcons.plus, size: 14),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Consumer(
                builder: (context, ref, _) {
                  final apiState = ref.watch(apiClientProvider);
                  return ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: apiState.environmentVariables.length,
                      itemBuilder: (context, index) {
                        final key = apiState.environmentVariables.keys.elementAt(index);
                        final value = apiState.environmentVariables[key]!;
                        return ListTile(
                          dense: true,
                          title: Text('{{${key}}}', style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                          subtitle: Text(value, style: const TextStyle(fontSize: 11)),
                          trailing: IconButton(
                            icon: const Icon(LucideIcons.trash_2, size: 12),
                            onPressed: () => ref.read(apiClientProvider.notifier).removeEnvironmentVariable(key),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final apiState = ref.watch(apiClientProvider);

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Row(
        children: [
          if (_showSidebar) _buildSidebar(apiState, colorScheme),
          Expanded(
            child: Column(
              children: [
                _buildToolbar(colorScheme),
                _buildRequestBar(apiState, colorScheme),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: _buildRequestPanel(colorScheme),
                      ),
                      Container(
                        width: 1,
                        color: colorScheme.outlineVariant,
                      ),
                      Expanded(
                        flex: 3,
                        child: _buildResponsePanel(apiState, colorScheme),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(ColorScheme colorScheme) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(_showSidebar ? LucideIcons.panel_left_close : LucideIcons.panel_left_open, size: 16),
            onPressed: () => setState(() => _showSidebar = !_showSidebar),
            tooltip: 'Toggle sidebar',
          ),
          const SizedBox(width: 4),
          Icon(LucideIcons.globe, size: 16, color: colorScheme.primary),
          const SizedBox(width: 6),
          Text('API Client', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          const Spacer(),
          IconButton(
            icon: const Icon(LucideIcons.settings_2, size: 16),
            onPressed: _showEnvVarsDialog,
            tooltip: 'Environment Variables',
          ),
        ],
      ),
    );
  }

  Widget _buildRequestBar(ApiClientState apiState, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: _getMethodColor(_selectedMethod).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: DropdownButton<String>(
              value: _selectedMethod,
              underline: const SizedBox(),
              isDense: true,
              items: _methods.map((m) => DropdownMenuItem(
                value: m,
                child: Text(m, style: TextStyle(
                  color: _getMethodColor(m),
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                )),
              )).toList(),
              onChanged: (v) => setState(() => _selectedMethod = v ?? 'GET'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _urlController,
              decoration: InputDecoration(
                hintText: 'https://api.example.com/endpoint',
                hintStyle: TextStyle(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: colorScheme.outline),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 13),
              onSubmitted: (_) => _sendRequest(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: apiState.isLoading ? null : _sendRequest,
            icon: apiState.isLoading
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(LucideIcons.send, size: 16),
            tooltip: 'Send Request',
          ),
          const SizedBox(width: 4),
          PopupMenuButton<String>(
            icon: const Icon(LucideIcons.save, size: 16),
            tooltip: 'Save to collection',
            onSelected: (collectionName) {
              final apiService = ref.read(apiClientProvider.notifier);
              final state = ref.read(apiClientProvider);
              final idx = state.collections.indexWhere((c) => c.name == collectionName);
              if (idx >= 0) {
                apiService.addToCollection(idx, ApiRequest(
                  method: _selectedMethod,
                  url: _urlController.text,
                  headers: Map.from(_headers),
                  body: _bodyController.text.isNotEmpty ? _bodyController.text : null,
                ));
              }
            },
            itemBuilder: (context) {
              final state = ref.read(apiClientProvider);
              if (state.collections.isEmpty) {
                return [const PopupMenuItem(value: '', child: Text('No collections'))];
              }
              return state.collections.map((c) => PopupMenuItem(
                value: c.name,
                child: Text(c.name),
              )).toList();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar(ApiClientState apiState, ColorScheme colorScheme) {
    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        border: Border(right: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TabBar(
                    controller: _sideTabController,
                    tabs: const [
                      Tab(text: 'Collections'),
                      Tab(text: 'History'),
                    ],
                    labelStyle: const TextStyle(fontSize: 11),
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                  ),
                ),
                IconButton(
                  icon: const Icon(LucideIcons.plus, size: 14),
                  onPressed: _showCreateCollectionDialog,
                  tooltip: 'New collection',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _sideTabController,
              children: [
                _buildCollectionsList(apiState, colorScheme),
                _buildHistoryList(apiState, colorScheme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCollectionsList(ApiClientState apiState, ColorScheme colorScheme) {
    if (apiState.collections.isEmpty) {
      return Center(
        child: Text('No collections', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: apiState.collections.length,
      itemBuilder: (context, colIndex) {
        final collection = apiState.collections[colIndex];
        return ExpansionTile(
          dense: true,
          title: Text(collection.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          leading: const Icon(LucideIcons.folder, size: 14),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${collection.requests.length}', style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant)),
              const Icon(LucideIcons.chevron_right, size: 12),
            ],
          ),
          children: collection.requests.asMap().entries.map((entry) {
            final req = entry.value;
            return ListTile(
              dense: true,
              contentPadding: const EdgeInsets.only(left: 32),
              title: Text(
                '${req.method} ${Uri.parse(req.url).path}',
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              leading: Text(req.method, style: TextStyle(fontSize: 9, color: _getMethodColor(req.method), fontWeight: FontWeight.w600)),
              onTap: () {
                setState(() {
                  _selectedMethod = req.method;
                  _urlController.text = req.url;
                  _headers.clear();
                  _headers.addAll(req.headers);
                  _bodyController.text = req.body ?? '';
                });
              },
              trailing: IconButton(
                icon: const Icon(LucideIcons.trash_2, size: 12),
                onPressed: () => ref.read(apiClientProvider.notifier).removeRequestFromCollection(colIndex, entry.key),
                visualDensity: VisualDensity.compact,
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildHistoryList(ApiClientState apiState, ColorScheme colorScheme) {
    return Center(
      child: Text('History', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
    );
  }

  Widget _buildRequestPanel(ColorScheme colorScheme) {
    return Column(
      children: [
        TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Headers'),
            Tab(text: 'Body'),
            Tab(text: 'Auth'),
          ],
          labelColor: colorScheme.primary,
          unselectedLabelColor: colorScheme.onSurfaceVariant,
          labelStyle: const TextStyle(fontSize: 12),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildHeadersTab(colorScheme),
              _buildBodyTab(colorScheme),
              _buildAuthTab(colorScheme),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeadersTab(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _headerKeyController,
                  decoration: const InputDecoration(hintText: 'Key', isDense: true),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _headerValueController,
                  decoration: const InputDecoration(hintText: 'Value', isDense: true),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              IconButton(
                onPressed: _addHeader,
                icon: const Icon(LucideIcons.plus, size: 14),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: _headers.length,
              itemBuilder: (context, index) {
                final key = _headers.keys.elementAt(index);
                final value = _headers[key]!;
                return ListTile(
                  dense: true,
                  title: Text(key, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                  subtitle: Text(value, style: const TextStyle(fontSize: 11)),
                  trailing: IconButton(
                    icon: const Icon(LucideIcons.trash_2, size: 12),
                    onPressed: () => setState(() => _headers.remove(key)),
                    visualDensity: VisualDensity.compact,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBodyTab(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: TextField(
        controller: _bodyController,
        maxLines: null,
        expands: true,
        decoration: InputDecoration(
          hintText: 'Request body (JSON)',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
          contentPadding: const EdgeInsets.all(12),
        ),
        style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
      ),
    );
  }

  Widget _buildAuthTab(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Add Authorization header in Headers tab',
              style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12)),
          const SizedBox(height: 12),
          Text('Common patterns:', style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 11)),
          const SizedBox(height: 4),
          _authPreset('Bearer Token', 'Authorization: Bearer <token>'),
          _authPreset('Basic Auth', 'Authorization: Basic <base64>'),
          _authPreset('API Key', 'X-API-Key: <key>'),
        ],
      ),
    );
  }

  Widget _authPreset(String label, String header) {
    return ListTile(
      dense: true,
      title: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
      subtitle: Text(header, style: const TextStyle(fontSize: 10, fontFamily: 'monospace')),
      onTap: () {
        final parts = header.split(': ');
        setState(() {
          _headers[parts[0]] = parts.sublist(1).join(': ');
        });
        _tabController.animateTo(0);
      },
    );
  }

  Widget _buildResponsePanel(ApiClientState apiState, ColorScheme colorScheme) {
    final response = apiState.lastResponse;

    if (response == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.arrow_down, size: 32, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3)),
            const SizedBox(height: 8),
            Text('Send a request to see response', style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12)),
          ],
        ),
      );
    }

    final formattedBody = _tryFormatJson(response.body);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: (response.isSuccess ? Colors.green : Colors.red).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${response.statusCode}',
                  style: TextStyle(
                    color: response.isSuccess ? Colors.green : Colors.red,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text('${response.duration.inMilliseconds}ms', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
              const SizedBox(width: 8),
              Text('${(response.size / 1024).toStringAsFixed(1)} KB', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
              const Spacer(),
              IconButton(
                icon: const Icon(LucideIcons.copy, size: 14),
                onPressed: () {},
                tooltip: 'Copy response',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              formattedBody,
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
            ),
          ),
        ),
      ],
    );
  }

  String _tryFormatJson(String body) {
    try {
      final parsed = jsonDecode(body);
      return const JsonEncoder.withIndent('  ').convert(parsed);
    } catch (_) {
      return body;
    }
  }

  Color _getMethodColor(String method) {
    switch (method) {
      case 'GET': return Colors.green;
      case 'POST': return Colors.blue;
      case 'PUT': return Colors.orange;
      case 'PATCH': return Colors.amber;
      case 'DELETE': return Colors.red;
      case 'HEAD': return Colors.purple;
      case 'OPTIONS': return Colors.teal;
      default: return Colors.grey;
    }
  }
}
