import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quantum_ide/core/services/network_inspector_service.dart';

class RestClientService {
  static final RestClientService _instance = RestClientService._internal();
  factory RestClientService() => _instance;
  RestClientService._internal();

  final List<RestRequestHistory> _history = [];
  List<RestRequestHistory> get history => List.unmodifiable(_history);

  Future<RestResponse> sendRequest(RestRequest request) async {
    final stopwatch = Stopwatch()..start();
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30)
      ..badCertificateCallback = (_, _, _) => true;
    try {
      final uri = Uri.parse(request.url);
      final httpRequest = await client.openUrl(request.method, uri);

      request.headers.forEach((key, value) {
        httpRequest.headers.set(key, value);
      });

      if (request.body != null && request.body!.isNotEmpty) {
        httpRequest.write(request.body);
      }

      final httpResponse = await httpRequest.close();
      stopwatch.stop();

      final responseBody = await httpResponse.transform(utf8.decoder).join();

      final responseHeaders = <String, String>{};
      httpResponse.headers.forEach((key, values) {
        responseHeaders[key] = values.join(', ');
      });

      final response = RestResponse(
        statusCode: httpResponse.statusCode,
        body: responseBody,
        headers: responseHeaders,
        duration: stopwatch.elapsed,
        size: responseBody.length,
      );

      _history.insert(
        0,
        RestRequestHistory(
          request: request,
          response: response,
          timestamp: DateTime.now(),
        ),
      );

      if (_history.length > 50) {
        _history.removeLast();
      }

      NetworkInspectorService.addRequest(
        NetworkRequestItem(
          id: '${DateTime.now().microsecondsSinceEpoch}',
          url: request.url,
          method: request.method,
          statusCode: response.statusCode,
          requestHeaders: Map<String, dynamic>.from(request.headers),
          requestData: request.body,
          responseHeaders: Map<String, dynamic>.from(responseHeaders),
          responseData: responseBody,
          timestamp: DateTime.now(),
          durationMs: stopwatch.elapsed.inMilliseconds,
        ),
      );

      return response;
    } catch (e) {
      stopwatch.stop();
      NetworkInspectorService.addRequest(
        NetworkRequestItem(
          id: '${DateTime.now().microsecondsSinceEpoch}',
          url: request.url,
          method: request.method,
          requestHeaders: Map<String, dynamic>.from(request.headers),
          requestData: request.body,
          timestamp: DateTime.now(),
          durationMs: stopwatch.elapsed.inMilliseconds,
          error: e.toString(),
        ),
      );
      return RestResponse(
        statusCode: 0,
        body: 'Error: $e',
        headers: {},
        duration: stopwatch.elapsed,
        size: 0,
        error: e.toString(),
      );
    } finally {
      client.close(force: true);
    }
  }
}

class RestRequest {
  final String method;
  final String url;
  final Map<String, String> headers;
  final String? body;
  final String contentType;

  const RestRequest({
    required this.method,
    required this.url,
    this.headers = const {},
    this.body,
    this.contentType = 'application/json',
  });
}

class RestResponse {
  final int statusCode;
  final String body;
  final Map<String, String> headers;
  final Duration duration;
  final int size;
  final String? error;

  const RestResponse({
    required this.statusCode,
    required this.body,
    required this.headers,
    required this.duration,
    required this.size,
    this.error,
  });

  bool get isSuccess => statusCode >= 200 && statusCode < 300;
}

class RestRequestHistory {
  final RestRequest request;
  final RestResponse response;
  final DateTime timestamp;

  const RestRequestHistory({
    required this.request,
    required this.response,
    required this.timestamp,
  });
}

final restClientServiceProvider = Provider<RestClientService>((ref) {
  return RestClientService();
});
