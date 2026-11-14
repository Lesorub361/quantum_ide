import 'dart:convert';
import 'package:meta/meta.dart';
import 'package:http/http.dart' as http;

/// A class that provides AI completion functionality.
/// Click here for documentation: [AICompletion](https://github.com/heckmon/flutter_code_crafter/blob/main/docs/AICompletion.md)
///
/// Example usage:
///
/// ```dart
///import 'package:flutter/material.dart';
///import 'package:code_crafter/code_crafter.dart';
///
///final aiCompletion = AiCompletion(
///    model: Gemini(
///        apiKey: "Your API Key",
///    )
///)
///```
///
///Then pass the `aiCompletion` instance to the `CodeCrafter` widget:
///
///```dart
///CodeCrafter(
///    controller: controller,
///    theme: anOldHopeTheme,
///    aiCompletion: aiCompletion, // Pass the AI completion instance here
///),
///```
///
class AiCompletion {
  /// The model to use for AI completion.
  ///
  /// This should be an instance of a class that extends [Models].
  /// Documentation and available models can be found here: [AICompletion](https://github.com/heckmon/flutter_code_crafter/blob/main/docs/AICompletion.md)
  Models model;

  /// Whether to enable AI completion. Defaults to true.
  bool enableCompletion;

  /// The debounce time in milliseconds for AI completion requests. Defaults to 1000ms.
  int debounceTime;

  /// Whether the completion is auto or manual
  /// Use [CompletionType.auto] for automatic completion and [CompletionType.manual] to invoke the completion on a callback or [CompletionType.mixed] for both.
  /// Defaults to [CompletionType.auto]
  CompletionType completionType;

  AiCompletion({
    required this.model,
    this.completionType = CompletionType.auto,
    this.debounceTime = 1000,
    this.enableCompletion = true,
  });
}

sealed class Models {
  /// API Url
  String get url;

  /// API key for the AI service, if required.
  String? get apiKey;

  /// The model to use for AI completion, if applicable.
  String? get model;

  /// Headers to include in the HTTP request.
  Map<String, String> get headers;

  @protected
  final String instruction =
      "You are a code completion engine. Given the provided code where the cursor is represented by the placeholder '<|CURSOR|>', generate only the code that should be inserted at that position. Do not include the placeholder or any explanations. Return only the code to insert.";

  Map<String, dynamic> buildRequest(String code);

  String responseParser(dynamic response);

  Future<String> completionResponse(String code) async {
    final uri = Uri.parse(url);
    final response = await http.post(
      uri,
      headers: headers,
      body: jsonEncode(buildRequest(code)),
    );
    if (response.statusCode == 200) {
      return _cleanCode(responseParser(jsonDecode(response.body)));
    }
    throw Exception(
      "Failed to load AI suggestion \nStatus code: ${response.statusCode}\n error: ${response.body}",
    );
  }

  @protected
  String _cleanCode(String raw) {
    final codeBlockRegex = RegExp(r'```(?:\w+)?\n([\s\S]*?)\n```');
    final thinkRegex = RegExp(r'<think>[\s\S]*?<\/think>');
    raw = raw.replaceAll(thinkRegex, '').trim();
    final match = codeBlockRegex.firstMatch(raw);
    if (match != null) return match.group(1)!.trim();

    return raw.trim();
  }
}

sealed class OpenAiCompatible extends Models {
  @protected
  String get baseUrl;
  @override
  String get url => "$baseUrl/chat/completions";

  @override
  Map<String, String> get headers => {
    "Content-Type": "application/json",
    "Authorization": "Bearer $apiKey",
  };

  @override
  Map<String, dynamic> buildRequest(String code) {
    return {
      "model": model,
      "messages": [
        {"role": "system", "content": instruction},
        {"role": "user", "content": code},
      ],
    };
  }

  @override
  String responseParser(dynamic response) {
    try {
      return response["choices"][0]["message"]["content"];
    } catch (e) {
      throw FormatException(
        "Failed to parse AI response: $e \nResponse: $response",
      );
    }
  }
}

/// Goole Gemini AI model implementation.
class Gemini extends Models {
  @override
  final String url, apiKey, model;
  @override
  Map<String, String> get headers => {'Content-Type': 'application/json'};
  int? temperature, maxOutputTokens, topP, topK, stopSequences;

  Gemini({
    required this.apiKey,
    this.model = 'gemini-2.0-flash',
    this.temperature,
    this.maxOutputTokens,
    this.topP,
    this.topK,
    this.stopSequences,
  }) : url =
           'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey';

  @override
  String responseParser(dynamic response) {
    try {
      return response["candidates"][0]["content"]["parts"][0]["text"];
    } catch (e) {
      throw FormatException(
        "Failed to parse AI response: $e \nResponse: $response",
      );
    }
  }

  @override
  Map<String, dynamic> buildRequest(String code) {
    return {
      "systemInstruction": {
        "parts": [
          {"text": instruction},
        ],
      },
      "contents": [
        {
          "parts": [
            {"text": code},
          ],
        },
      ],
      "generationConfig": {
        "stopSequences": ["Title"],
        "temperature": temperature ?? 1.0,
        "maxOutputTokens": maxOutputTokens ?? 800,
        "topP": topP ?? 0.8,
        "topK": topK ?? 10,
      },
    };
  }
}

/// OpenAI AI model implementation.
class OpenAI extends Models {
  @override
  final String url = 'https://api.openai.com/v1/responses', apiKey, model;

  OpenAI({required this.apiKey, required this.model});

  @override
  String responseParser(dynamic response) {
    try {
      return response[0]["content"][0]["text"];
    } catch (e) {
      throw FormatException(
        "Failed to parse AI response: $e \nResponse: $response",
      );
    }
  }

  @override
  Map<String, String> get headers => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $apiKey',
  };

  @override
  Map<String, dynamic> buildRequest(String code) {
    return {"model": model, "instructions": instruction, "input": code};
  }
}

/// Claude AI model implementation.
class Claude extends Models {
  @override
  final String url = 'https://api.anthropic.com/v1/messages', apiKey, model;

  Claude({required this.apiKey, required this.model});

  @override
  String responseParser(dynamic response) {
    try {
      return response["content"][0]["text"];
    } catch (e) {
      throw FormatException(
        "Failed to parse AI response: $e \nResponse: $response",
      );
    }
  }

  @override
  Map<String, String> get headers => {
    'Content-Type': 'application/json',
    'x-api-key': apiKey,
  };

  @override
  Map<String, dynamic> buildRequest(String code) {
    return {
      "model": model,
      "max_tokens": 1024,
      "system": instruction,
      "messages": [
        {"role": "user", "content": code},
      ],
    };
  }
}

/// Grok aka xAI AI model implementation.
class Grok extends OpenAiCompatible {
  @override
  String get baseUrl => "https://api.x.ai/v1";
  @override
  final String apiKey, model;
  Grok({required this.apiKey, required this.model});
}

/// DeepSeek AI model implementation.
class DeepSeek extends OpenAiCompatible {
  @override
  String get baseUrl => "https://api.deepseek.com";
  @override
  final String apiKey, model;
  DeepSeek({required this.apiKey, required this.model});
}

/// Groq AI model implementation.
class Gorq extends OpenAiCompatible {
  @override
  String get baseUrl => "https://api.groq.com/openai/v1";
  @override
  final String apiKey, model;
  Gorq({required this.apiKey, required this.model});
}

/// Together AI model implementation.
class TogetherAi extends OpenAiCompatible {
  @override
  String get baseUrl => "https://api.together.xyz/v1";
  @override
  final String apiKey, model;
  TogetherAi({required this.apiKey, required this.model});
}

/// Sonar AI model implementation.
class Sonar extends OpenAiCompatible {
  @override
  String get baseUrl => "https://api.perplexity.ai";
  @override
  final String apiKey, model;
  Sonar({required this.apiKey, required this.model});
}

/// OpenRouter AI model implementation.
class OpenRouter extends OpenAiCompatible {
  @override
  String get baseUrl => "https://openrouter.ai/api/v1";
  @override
  final String apiKey, model;
  OpenRouter({required this.apiKey, required this.model});
}

/// FireWorks AI model implementation.
class FireWorks extends OpenAiCompatible {
  @override
  String get baseUrl => "https://api.fireworks.ai/inference/v1";
  @override
  final String apiKey, model;
  FireWorks({required this.apiKey, required this.model});
}

/// Custom AI model implementation that allows for custom API endpoints and request/response handling.
///
/// Example usage:
///
/// ```dart
///late final Models model;
///
///  @override
///  void initState() {
///    model = CustomModel(
///      url: "https://api.together.xyz/v1/chat/completions",
///      customHeaders: {
///        "Authorization": "Bearer ${your_api_key}",
///        "Content-Type": "application/json"
///      },
///      requestBuilder: (code, instruction){
///       return {
///          "model": "deepseek-ai/DeepSeek-V3",
///          "messages": [
///            {
///              "role": "system",
///             "content": instruction
///            },
///            {
///              "role": "user",
///              "content": code
///           }
///          ]
///        };
///      },
///      customParser: (response) => response['choices'][0]['message']['content']
///    );
///    controller = CodeCrafterController();
///    controller.language = python;
///    super.initState();
///  }
///```
///Then pass the `model` instance to the `AiCompletion` class:

///```dart
/// @override
///  Widget build(BuildContext context) {
///    return MaterialApp(
///      home: Scaffold(
///        body: CodeCrafter(
///          editorTheme: anOldHopeTheme,
///          controller: controller,
///          aiCompletion: AiCompletion(
///            model: model // Pass the custom model here
///          ),
///        )
///      ),
///    );
/// }
///```
class CustomModel extends Models {
  /// The URL for the custom AI service endpoint.
  @override
  final String url;
  @override
  String? get apiKey => null;
  @override
  String? get model => null;
  final String httpMethod;
  final Map<String, String> customHeaders;
  final Map<String, dynamic> Function(String code, String instruction)?
  requestBuilder;
  final String Function(dynamic response) customParser;

  CustomModel({
    required this.url,
    required this.customHeaders,
    required this.requestBuilder,
    required this.customParser,
    this.httpMethod = 'POST',
  });

  @override
  String responseParser(dynamic response) {
    try {
      return customParser(response);
    } catch (e) {
      throw FormatException(
        "Failed to parse AI response: $e \nResponse: $response",
      );
    }
  }

  @override
  Map<String, String> get headers {
    final headers = {'Content-Type': 'application/json', ...customHeaders};

    return headers;
  }

  @override
  Map<String, dynamic> buildRequest(String code) {
    if (requestBuilder != null) {
      return requestBuilder!(code, instruction);
    }
    return {
      if (model != null) 'model': model,
      'code': code,
      'parameters': {'instruction': instruction, 'temperature': 0.2},
    };
  }

  @override
  Future<String> completionResponse(String code) async {
    try {
      final uri = Uri.parse(url);
      final response = httpMethod.toUpperCase() == 'GET'
          ? await http.get(uri, headers: headers)
          : await http.post(
              uri,
              headers: headers,
              body: jsonEncode(buildRequest(code)),
            );

      if (response.statusCode == 200) {
        return responseParser(jsonDecode(response.body));
      } else {
        throw Exception(
          'Request failed with status ${response.statusCode}\n ${response.body}\n$uri',
        );
      }
    } catch (e) {
      throw Exception('Failed to complete request: $e');
    }
  }
}

/// Enum that defines the type of AI completion behavior.
enum CompletionType {
  /// Completion is triggered automatically based on the debounce time.
  /// This is the default behavior.
  auto,

  /// Completion is triggered manually, typically through the getManualAiCompletion() callback in the [CodeCrafterController].
  /// eg:
  /// ```dart
  /// controller.getManualAiCompletion();
  /// ```
  ///
  /// Use this when you have a very limited number of requests to the AI service, or when you want to control when the AI completion is invoked.
  manual,

  /// Completion shown automatically, but it can be triggered manually using the callback at will.
  mixed,
}
