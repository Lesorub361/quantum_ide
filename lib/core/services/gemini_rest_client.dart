import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

/// Minimal Gemini REST client.
///
/// Replaces the deprecated `google_generative_ai` package. Talks directly to
/// the Generative Language API (`generateContent` / `streamGenerateContent`)
/// using the app-wide Dio instance.
class GeminiRestClient {
  static const String defaultBaseUrl =
      'https://generativelanguage.googleapis.com/v1beta';

  final Dio _dio;
  final String apiKey;
  final String model;
  final String baseUrl;

  GeminiRestClient({
    required Dio dio,
    required this.apiKey,
    required this.model,
    this.baseUrl = defaultBaseUrl,
  }) : _dio = dio;

  String get _modelPath =>
      model.startsWith('models/') || model.startsWith('tunedModels/')
          ? model
          : 'models/$model';

  Options get _options => Options(
        headers: {
          'x-goog-api-key': apiKey,
          'Content-Type': 'application/json',
        },
      );

  /// Builds a single content entry. [role] is `user` or `model`.
  static Map<String, dynamic> content(
    String role,
    String text, {
    String? imageBase64,
    String imageMimeType = 'image/jpeg',
  }) {
    return {
      'role': role,
      'parts': [
        if (imageBase64 != null)
          {
            'inline_data': {'mime_type': imageMimeType, 'data': imageBase64},
          },
        {'text': text},
      ],
    };
  }

  /// Converts the app's `[{role, content}]` history into Gemini contents.
  static List<Map<String, dynamic>> historyToContents(
    List<Map<String, String>> history,
  ) {
    return [
      for (final m in history)
        content(m['role'] == 'user' ? 'user' : 'model', m['content'] ?? ''),
    ];
  }

  Map<String, dynamic> _body(
    List<Map<String, dynamic>> contents,
    String? systemInstruction,
  ) {
    return {
      'contents': contents,
      if (systemInstruction != null && systemInstruction.isNotEmpty)
        'systemInstruction': {
          'parts': [
            {'text': systemInstruction},
          ],
        },
    };
  }

  /// Non-streaming generation.
  Future<GeminiResult> generate(
    List<Map<String, dynamic>> contents, {
    String? systemInstruction,
  }) async {
    try {
      final resp = await _dio.post<dynamic>(
        '$baseUrl/$_modelPath:generateContent',
        options: _options,
        data: jsonEncode(_body(contents, systemInstruction)),
      );
      final data = resp.data is String ? jsonDecode(resp.data) : resp.data;
      return GeminiResult.fromJson(data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw GeminiException(_describe(e));
    }
  }

  /// Streaming generation via Server-Sent Events.
  Stream<GeminiResult> generateStream(
    List<Map<String, dynamic>> contents, {
    String? systemInstruction,
  }) async* {
    Response<ResponseBody> resp;
    try {
      resp = await _dio.post<ResponseBody>(
        '$baseUrl/$_modelPath:streamGenerateContent',
        queryParameters: {'alt': 'sse'},
        options: _options.copyWith(responseType: ResponseType.stream),
        data: jsonEncode(_body(contents, systemInstruction)),
      );
    } on DioException catch (e) {
      throw GeminiException(_describe(e));
    }

    final lines = resp.data!.stream
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter());

    await for (final line in lines) {
      if (!line.startsWith('data:')) continue;
      final payload = line.substring(5).trim();
      if (payload.isEmpty || payload == '[DONE]') continue;
      try {
        yield GeminiResult.fromJson(jsonDecode(payload) as Map<String, dynamic>);
      } catch (_) {
        // Skip malformed chunk
      }
    }
  }

  static String _describe(DioException e) {
    final data = e.response?.data;
    try {
      final map = data is String ? jsonDecode(data) : data;
      final msg = map?['error']?['message'];
      if (msg != null) return 'Gemini ${e.response?.statusCode}: $msg';
    } catch (_) {}
    return e.response?.statusCode != null
        ? 'Gemini HTTP ${e.response!.statusCode}: ${e.message}'
        : 'Gemini network error: ${e.message}';
  }
}

class GeminiResult {
  final String? text;
  final int? promptTokens;
  final int? completionTokens;

  const GeminiResult({this.text, this.promptTokens, this.completionTokens});

  factory GeminiResult.fromJson(Map<String, dynamic> json) {
    final candidates = json['candidates'] as List?;
    String? text;
    if (candidates != null && candidates.isNotEmpty) {
      final parts = candidates.first?['content']?['parts'] as List?;
      if (parts != null) {
        final buf = StringBuffer();
        for (final part in parts) {
          final t = part?['text'];
          if (t is String) buf.write(t);
        }
        if (buf.isNotEmpty) text = buf.toString();
      }
    }
    final usage = json['usageMetadata'] as Map<String, dynamic>?;
    return GeminiResult(
      text: text,
      promptTokens: usage?['promptTokenCount'] as int?,
      completionTokens: usage?['candidatesTokenCount'] as int?,
    );
  }
}

class GeminiException implements Exception {
  final String message;
  GeminiException(this.message);
  @override
  String toString() => message;
}
