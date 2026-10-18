import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'talker_service.dart';

class NetworkRequestItem {
  final String id;
  final String url;
  final String method;
  final int? statusCode;
  final String? statusMessage;
  final Map<String, dynamic> requestHeaders;
  final dynamic requestData;
  final Map<String, dynamic>? responseHeaders;
  final dynamic responseData;
  final DateTime timestamp;
  final int durationMs;
  final String? error;

  NetworkRequestItem({
    required this.id,
    required this.url,
    required this.method,
    this.statusCode,
    this.statusMessage,
    required this.requestHeaders,
    this.requestData,
    this.responseHeaders,
    this.responseData,
    required this.timestamp,
    required this.durationMs,
    this.error,
  });

  bool get isSuccess => statusCode != null && statusCode! >= 200 && statusCode! < 300;

  String toCurl() {
    final buffer = StringBuffer('curl -X $method "$url"');
    for (final entry in requestHeaders.entries) {
      buffer.write(' \\\n  -H "${entry.key}: ${entry.value}"');
    }
    if (requestData != null) {
      String dataStr;
      if (requestData is String) {
        dataStr = requestData as String;
      } else {
        try {
          dataStr = jsonEncode(requestData);
        } catch (_) {
          dataStr = requestData.toString();
        }
      }
      buffer.write(' \\\n  -d \x27$dataStr\x27');
    }
    return buffer.toString();
  }
}

class NetworkInspectorService {
  static final ValueNotifier<List<NetworkRequestItem>> requestsNotifier =
      ValueNotifier<List<NetworkRequestItem>>([]);

  static bool _initialized = false;

  static void init() {
    _initialized = true;
  }

  static bool get isInitialized => _initialized;

  static void clear() {
    requestsNotifier.value = [];
  }

  static void addRequest(NetworkRequestItem item) {
    final list = List<NetworkRequestItem>.from(requestsNotifier.value);
    list.insert(0, item);
    if (list.length > 200) {
      list.removeLast();
    }
    requestsNotifier.value = list;
  }

  static Interceptor get dioInterceptor => _NetworkInspectorInterceptor();

  static void showInspector(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const NetworkInspectorScreen(),
      ),
    );
  }
}

class _NetworkInspectorInterceptor extends Interceptor {
  final Map<RequestOptions, DateTime> _startTimes = {};

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    _startTimes[options] = DateTime.now();
    super.onRequest(options, handler);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final start = _startTimes.remove(response.requestOptions) ?? DateTime.now();
    final duration = DateTime.now().difference(start).inMilliseconds;

    final item = NetworkRequestItem(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      url: response.requestOptions.uri.toString(),
      method: response.requestOptions.method,
      statusCode: response.statusCode,
      statusMessage: response.statusMessage,
      requestHeaders: Map<String, dynamic>.from(response.requestOptions.headers),
      requestData: response.requestOptions.data,
      responseHeaders: response.headers.map.map((k, v) => MapEntry(k, v.join(', '))),
      responseData: response.data,
      timestamp: start,
      durationMs: duration,
    );
    NetworkInspectorService.addRequest(item);
    TalkerService.info('[HTTP ${item.method}] ${item.statusCode} ${item.url} (${duration}ms)');

    super.onResponse(response, handler);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final start = _startTimes.remove(err.requestOptions) ?? DateTime.now();
    final duration = DateTime.now().difference(start).inMilliseconds;

    final item = NetworkRequestItem(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      url: err.requestOptions.uri.toString(),
      method: err.requestOptions.method,
      statusCode: err.response?.statusCode,
      statusMessage: err.response?.statusMessage ?? err.message,
      requestHeaders: Map<String, dynamic>.from(err.requestOptions.headers),
      requestData: err.requestOptions.data,
      responseHeaders: err.response?.headers.map.map((k, v) => MapEntry(k, v.join(', '))),
      responseData: err.response?.data,
      timestamp: start,
      durationMs: duration,
      error: err.toString(),
    );
    NetworkInspectorService.addRequest(item);
    TalkerService.error('[HTTP ${item.method} ERROR] ${item.statusCode ?? "FAIL"} ${item.url} (${duration}ms): ${err.message}');

    super.onError(err, handler);
  }
}

class NetworkInspectorScreen extends StatefulWidget {
  const NetworkInspectorScreen({super.key});

  @override
  State<NetworkInspectorScreen> createState() => _NetworkInspectorScreenState();
}

class _NetworkInspectorScreenState extends State<NetworkInspectorScreen> {
  String _filterMethod = 'ALL';
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF12141C) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Network Inspector', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.trash_2, size: 20),
            tooltip: 'Очистить запросы',
            onPressed: () {
              NetworkInspectorService.clear();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('История сети очищена'), duration: Duration(seconds: 1)),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Search & Filter Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: isDark ? const Color(0xFF1E2230) : Colors.white,
            child: Column(
              children: [
                TextField(
                  onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
                  decoration: InputDecoration(
                    hintText: 'Поиск по URL или пути...',
                    prefixIcon: const Icon(LucideIcons.search, size: 18),
                    filled: true,
                    fillColor: isDark ? const Color(0xFF12141C) : const Color(0xFFF1F5F9),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: ['ALL', 'GET', 'POST', 'PUT', 'DELETE', 'PATCH'].map((method) {
                      final isSelected = _filterMethod == method;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          label: Text(method, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          selected: isSelected,
                          onSelected: (_) => setState(() => _filterMethod = method),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Request list
          Expanded(
            child: ValueListenableBuilder<List<NetworkRequestItem>>(
              valueListenable: NetworkInspectorService.requestsNotifier,
              builder: (context, requests, _) {
                final filtered = requests.where((item) {
                  if (_filterMethod != 'ALL' && item.method.toUpperCase() != _filterMethod) {
                    return false;
                  }
                  if (_searchQuery.isNotEmpty && !item.url.toLowerCase().contains(_searchQuery)) {
                    return false;
                  }
                  return true;
                }).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(LucideIcons.activity, size: 54, color: Colors.grey.withValues(alpha: 0.4)),
                        const SizedBox(height: 12),
                        const Text('Нет записанных HTTP запросов', style: TextStyle(color: Colors.grey, fontSize: 15)),
                        const SizedBox(height: 4),
                        const Text('Запросы через сетевой клиент будут отображаться здесь', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = filtered[index];
                    return _buildRequestTile(context, item);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestTile(BuildContext context, NetworkRequestItem item) {
    Color statusColor;
    if (item.statusCode == null) {
      statusColor = Colors.grey;
    } else if (item.statusCode! >= 200 && item.statusCode! < 300) {
      statusColor = const Color(0xFF10B981);
    } else if (item.statusCode! >= 300 && item.statusCode! < 400) {
      statusColor = Colors.blue;
    } else if (item.statusCode! >= 400 && item.statusCode! < 500) {
      statusColor = Colors.orange;
    } else {
      statusColor = Colors.red;
    }

    final uri = Uri.tryParse(item.url);
    final path = uri?.path.isNotEmpty == true ? uri!.path : item.url;
    final host = uri?.host ?? '';

    return ListTile(
      onTap: () => _showRequestDetails(context, item),
      leading: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: statusColor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: statusColor.withValues(alpha: 0.4)),
        ),
        child: Text(
          item.statusCode?.toString() ?? 'ERR',
          style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 13),
        ),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              item.method,
              style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 11),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
        ],
      ),
      subtitle: Row(
        children: [
          if (host.isNotEmpty) ...[
            Text(host, style: const TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(width: 8),
          ],
          Text('${item.durationMs}ms', style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
      trailing: const Icon(LucideIcons.chevron_right, size: 16, color: Colors.grey),
    );
  }

  void _showRequestDetails(BuildContext context, NetworkRequestItem item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return _RequestDetailsSheet(item: item, scrollController: scrollController);
          },
        );
      },
    );
  }
}

class _RequestDetailsSheet extends StatelessWidget {
  final NetworkRequestItem item;
  final ScrollController scrollController;

  const _RequestDetailsSheet({required this.item, required this.scrollController});

  String _formatBody(dynamic body) {
    if (body == null) return 'No body';
    if (body is String) {
      try {
        final decoded = jsonDecode(body);
        return const JsonEncoder.withIndent('  ').convert(decoded);
      } catch (_) {
        return body;
      }
    }
    try {
      return const JsonEncoder.withIndent('  ').convert(body);
    } catch (_) {
      return body.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView(
        controller: scrollController,
        children: [
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text('${item.method} Request', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const Spacer(),
              ElevatedButton.icon(
                icon: const Icon(LucideIcons.copy, size: 14),
                label: const Text('cURL', style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(visualDensity: VisualDensity.compact),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: item.toCurl()));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('cURL команда скопирована в буфер'), duration: Duration(seconds: 1)),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E2230) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: SelectableText(item.url, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
          ),
          const SizedBox(height: 16),
          _sectionHeader('Обзор'),
          _infoRow('Status', '${item.statusCode ?? "None"} ${item.statusMessage ?? ""}'),
          _infoRow('Duration', '${item.durationMs} ms'),
          _infoRow('Timestamp', item.timestamp.toIso8601String()),
          if (item.error != null) _infoRow('Error', item.error!, isError: true),
          const SizedBox(height: 16),
          _sectionHeader('Заголовки запроса'),
          _codeBox(context, item.requestHeaders.entries.map((e) => '${e.key}: ${e.value}').join('\n')),
          if (item.requestData != null) ...[
            const SizedBox(height: 16),
            _sectionHeader('Тело запроса'),
            _codeBox(context, _formatBody(item.requestData)),
          ],
          if (item.responseHeaders != null && item.responseHeaders!.isNotEmpty) ...[
            const SizedBox(height: 16),
            _sectionHeader('Заголовки ответа'),
            _codeBox(context, item.responseHeaders!.entries.map((e) => '${e.key}: ${e.value}').join('\n')),
          ],
          const SizedBox(height: 16),
          _sectionHeader('Тело ответа'),
          _codeBox(context, _formatBody(item.responseData)),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
    );
  }

  Widget _infoRow(String label, String value, {bool isError = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 100, child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12))),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isError ? Colors.redAccent : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _codeBox(BuildContext context, String code) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F1117) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: SelectableText(
        code.isEmpty ? 'Empty' : code,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
      ),
    );
  }
}
