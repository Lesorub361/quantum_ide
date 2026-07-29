import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/core/services/workspace_service.dart';

class ApiRequest {
  final String method;
  final String url;
  final Map<String, String> headers;
  final String? body;
  final String contentType;
  final Map<String, String>? variables;

  const ApiRequest({
    required this.method,
    required this.url,
    this.headers = const {},
    this.body,
    this.contentType = 'application/json',
    this.variables,
  });

  factory ApiRequest.fromJson(Map<String, dynamic> json) {
    return ApiRequest(
      method: json['method'] ?? 'GET',
      url: json['url'] ?? '',
      headers: Map<String, String>.from(json['headers'] ?? {}),
      body: json['body'],
      contentType: json['contentType'] ?? 'application/json',
      variables: json['variables'] != null ? Map<String, String>.from(json['variables']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'method': method,
      'url': url,
      'headers': headers,
      if (body != null) 'body': body,
      'contentType': contentType,
      if (variables != null) 'variables': variables,
    };
  }
}

class ApiResponse {
  final int statusCode;
  final String body;
  final Map<String, String> headers;
  final Duration duration;
  final int size;
  final String? error;
  final bool isGraphql;

  const ApiResponse({
    required this.statusCode,
    required this.body,
    required this.headers,
    required this.duration,
    required this.size,
    this.error,
    this.isGraphql = false,
  });

  bool get isSuccess => statusCode >= 200 && statusCode < 300;
}

class ApiCollection {
  final String name;
  final List<ApiRequest> requests;

  const ApiCollection({required this.name, required this.requests});

  factory ApiCollection.fromJson(Map<String, dynamic> json) {
    return ApiCollection(
      name: json['name'] ?? '',
      requests: (json['requests'] as List<dynamic>? ?? [])
          .map((r) => ApiRequest.fromJson(r))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'requests': requests.map((r) => r.toJson()).toList(),
    };
  }
}

class ApiClientState {
  final List<ApiCollection> collections;
  final ApiResponse? lastResponse;
  final bool isLoading;
  final Map<String, String> environmentVariables;

  const ApiClientState({
    this.collections = const [],
    this.lastResponse,
    this.isLoading = false,
    this.environmentVariables = const {},
  });

  ApiClientState copyWith({
    List<ApiCollection>? collections,
    ApiResponse? lastResponse,
    bool? isLoading,
    Map<String, String>? environmentVariables,
  }) {
    return ApiClientState(
      collections: collections ?? this.collections,
      lastResponse: lastResponse ?? this.lastResponse,
      isLoading: isLoading ?? this.isLoading,
      environmentVariables: environmentVariables ?? this.environmentVariables,
    );
  }
}

class ApiClientService extends StateNotifier<ApiClientState> {
  final Ref ref;

  ApiClientService(this.ref) : super(const ApiClientState()) {
    _loadCollections();
  }

  Future<void> _loadCollections() async {
    final workspacePath = ref.read(workspaceProvider).currentPath;
    if (workspacePath == null) return;

    final collectionFile = File(p.join(workspacePath, '.quantum', 'api_collection.json'));
    if (!await collectionFile.exists()) return;

    try {
      final content = await collectionFile.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      final collections = (json['collections'] as List<dynamic>? ?? [])
          .map((c) => ApiCollection.fromJson(c))
          .toList();
      final envVars = Map<String, String>.from(json['environment'] ?? {});
      state = state.copyWith(collections: collections, environmentVariables: envVars);
    } catch (e) {
      debugPrint('Failed to load API collections: $e');
    }
  }

  Future<void> saveCollections() async {
    final workspacePath = ref.read(workspaceProvider).currentPath;
    if (workspacePath == null) return;

    final dir = Directory(p.join(workspacePath, '.quantum'));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    final collectionFile = File(p.join(workspacePath, '.quantum', 'api_collection.json'));
    final json = {
      'collections': state.collections.map((c) => c.toJson()).toList(),
      'environment': state.environmentVariables,
    };
    await collectionFile.writeAsString(const JsonEncoder.withIndent('  ').convert(json));
  }

  String _resolveVariables(String text) {
    var resolved = text;
    for (final entry in state.environmentVariables.entries) {
      resolved = resolved.replaceAll('{{${entry.key}}}', entry.value);
    }
    return resolved;
  }

  Future<ApiResponse> sendRequest(ApiRequest request) async {
    state = state.copyWith(isLoading: true);

    final stopwatch = Stopwatch()..start();
    try {
      final resolvedUrl = _resolveVariables(request.url);
      final resolvedHeaders = request.headers.map(
        (k, v) => MapEntry(k, _resolveVariables(v)),
      );
      final resolvedBody = request.body != null ? _resolveVariables(request.body!) : null;

      final uri = Uri.parse(resolvedUrl);
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 30);
      client.badCertificateCallback = (_, _, _) => true;

      final httpRequest = await client.openUrl(request.method, uri);

      resolvedHeaders.forEach((key, value) {
        httpRequest.headers.set(key, value);
      });

      if (resolvedBody != null && resolvedBody.isNotEmpty) {
        httpRequest.write(resolvedBody);
      }

      final httpResponse = await httpRequest.close();
      stopwatch.stop();

      final responseBody = await httpResponse.transform(utf8.decoder).join();

      final responseHeaders = <String, String>{};
      httpResponse.headers.forEach((key, values) {
        responseHeaders[key] = values.join(', ');
      });

      final isGraphql = request.contentType == 'application/json' &&
          resolvedBody != null &&
          resolvedBody.contains('"query"');

      final response = ApiResponse(
        statusCode: httpResponse.statusCode,
        body: responseBody,
        headers: responseHeaders,
        duration: stopwatch.elapsed,
        size: responseBody.length,
        isGraphql: isGraphql,
      );

      state = state.copyWith(lastResponse: response, isLoading: false);
      return response;
    } catch (e) {
      stopwatch.stop();
      final response = ApiResponse(
        statusCode: 0,
        body: 'Error: $e',
        headers: {},
        duration: stopwatch.elapsed,
        size: 0,
        error: e.toString(),
      );
      state = state.copyWith(lastResponse: response, isLoading: false);
      return response;
    }
  }

  Future<void> addToCollection(int collectionIndex, ApiRequest request) async {
    final collections = List<ApiCollection>.from(state.collections);
    if (collectionIndex < 0 || collectionIndex >= collections.length) return;

    final collection = collections[collectionIndex];
    collections[collectionIndex] = ApiCollection(
      name: collection.name,
      requests: [...collection.requests, request],
    );
    state = state.copyWith(collections: collections);
    await saveCollections();
  }

  Future<void> createCollection(String name) async {
    state = state.copyWith(
      collections: [...state.collections, ApiCollection(name: name, requests: [])],
    );
    await saveCollections();
  }

  Future<void> removeCollection(int index) async {
    final collections = List<ApiCollection>.from(state.collections);
    if (index < 0 || index >= collections.length) return;
    collections.removeAt(index);
    state = state.copyWith(collections: collections);
    await saveCollections();
  }

  Future<void> removeRequestFromCollection(int collectionIndex, int requestIndex) async {
    final collections = List<ApiCollection>.from(state.collections);
    if (collectionIndex < 0 || collectionIndex >= collections.length) return;

    final collection = collections[collectionIndex];
    final requests = List<ApiRequest>.from(collection.requests);
    if (requestIndex < 0 || requestIndex >= requests.length) return;

    requests.removeAt(requestIndex);
    collections[collectionIndex] = ApiCollection(name: collection.name, requests: requests);
    state = state.copyWith(collections: collections);
    await saveCollections();
  }

  Future<void> setEnvironmentVariable(String key, String value) async {
    final envVars = Map<String, String>.from(state.environmentVariables);
    envVars[key] = value;
    state = state.copyWith(environmentVariables: envVars);
    await saveCollections();
  }

  Future<void> removeEnvironmentVariable(String key) async {
    final envVars = Map<String, String>.from(state.environmentVariables);
    envVars.remove(key);
    state = state.copyWith(environmentVariables: envVars);
    await saveCollections();
  }
}

final apiClientProvider = StateNotifierProvider<ApiClientService, ApiClientState>((ref) {
  return ApiClientService(ref);
});
