import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:quantum_ide/core/services/rest_client_service.dart';

class RestClientPage extends StatefulWidget {
  const RestClientPage({super.key});

  @override
  State<RestClientPage> createState() => _RestClientPageState();
}

class _RestClientPageState extends State<RestClientPage> {
  final _urlController = TextEditingController();
  final _bodyController = TextEditingController();
  final _headerKeyController = TextEditingController();
  final _headerValueController = TextEditingController();
  String _selectedMethod = 'GET';
  final Map<String, String> _headers = {'Content-Type': 'application/json'};
  RestResponse? _response;
  bool _isLoading = false;
  final _methods = ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS'];

  @override
  void dispose() {
    _urlController.dispose();
    _bodyController.dispose();
    _headerKeyController.dispose();
    _headerValueController.dispose();
    super.dispose();
  }

  Future<void> _sendRequest() async {
    if (_urlController.text.isEmpty) return;
    setState(() => _isLoading = true);

    final request = RestRequest(
      method: _selectedMethod,
      url: _urlController.text,
      headers: Map.from(_headers),
      body: _bodyController.text.isNotEmpty ? _bodyController.text : null,
    );

    final service = RestClientService();
    final response = await service.sendRequest(request);

    setState(() {
      _response = response;
      _isLoading = false;
    });
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              border: Border(
                bottom: BorderSide(color: colorScheme.outlineVariant),
              ),
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
                  onPressed: _isLoading ? null : _sendRequest,
                  icon: _isLoading
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(LucideIcons.send, size: 16),
                  tooltip: 'Send Request',
                ),
              ],
            ),
          ),
          Expanded(
            child: DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  TabBar(
                    tabs: const [
                      Tab(text: 'Body'),
                      Tab(text: 'Headers'),
                    ],
                    labelColor: colorScheme.primary,
                    unselectedLabelColor: colorScheme.onSurfaceVariant,
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: TextField(
                            controller: _bodyController,
                            maxLines: null,
                            expands: true,
                            decoration: InputDecoration(
                              hintText: 'Request body (JSON)',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                              contentPadding: const EdgeInsets.all(12),
                            ),
                            style: const TextStyle(
                              fontSize: 13,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _headerKeyController,
                                      decoration: const InputDecoration(
                                        hintText: 'Key',
                                        isDense: true,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextField(
                                      controller: _headerValueController,
                                      decoration: const InputDecoration(
                                        hintText: 'Value',
                                        isDense: true,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: _addHeader,
                                    icon: const Icon(LucideIcons.plus, size: 16),
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
                                      title: Text(key, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                                      subtitle: Text(value, style: const TextStyle(fontSize: 12)),
                                      trailing: IconButton(
                                        icon: const Icon(LucideIcons.trash_2, size: 14),
                                        onPressed: () => setState(() => _headers.remove(key)),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_response != null) _buildResponsePanel(colorScheme),
        ],
      ),
    );
  }

  Widget _buildResponsePanel(ColorScheme colorScheme) {
    final resp = _response!;
    final formattedBody = _tryFormatJson(resp.body);

    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: (resp.isSuccess ? Colors.green : Colors.red).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${resp.statusCode}',
                    style: TextStyle(
                      color: resp.isSuccess ? Colors.green : Colors.red,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${resp.duration.inMilliseconds}ms',
                  style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(width: 8),
                Text(
                  '${(resp.size / 1024).toStringAsFixed(1)} KB',
                  style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(LucideIcons.copy, size: 14),
                  onPressed: () {
                    // Copy to clipboard
                  },
                  tooltip: 'Copy response',
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                formattedBody,
                style: const TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
        ],
      ),
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
