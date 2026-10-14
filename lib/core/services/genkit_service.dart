import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:genkit/genkit.dart';
import 'package:genkit_google_genai/genkit_google_genai.dart';
import 'package:genkit_openai/genkit_openai.dart';
import 'package:genkit_anthropic/genkit_anthropic.dart';
import 'package:genkit_middleware/genkit_middleware.dart';
import 'package:schemantic/schemantic.dart';

import 'package:quantum_ide/core/models/ai_provider_config.dart';
import 'package:quantum_ide/core/services/ai_service.dart';
import 'package:quantum_ide/core/services/ai_tool_definitions.dart';
import 'package:quantum_ide/core/services/enhanced_ai_tool_executor.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';

/// Represents an interrupted tool call waiting for user confirmation in QuantumIDE.
class GenkitInterruptInfo {
  final ToolRequestPart requestPart;
  final String toolName;
  final Map<String, dynamic> arguments;
  final String risk;

  const GenkitInterruptInfo({
    required this.requestPart,
    required this.toolName,
    required this.arguments,
    required this.risk,
  });
}

/// The result of a Genkit generation step in QuantumIDE.
class GenkitResponse {
  final String text;
  final bool isInterrupted;
  final List<GenkitInterruptInfo> interrupts;
  final FinishReason finishReason;
  final int promptTokens;
  final int completionTokens;
  final int totalTokens;
  final GenerateResult? rawResult;

  const GenkitResponse({
    this.text = '',
    this.isInterrupted = false,
    this.interrupts = const [],
    this.finishReason = FinishReason.unknown,
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.totalTokens = 0,
    this.rawResult,
  });
}

/// Core Genkit 1.0 Service for QuantumIDE.
///
/// Unifies model access (Gemini, Claude, OpenAI, DeepSeek, Groq, Ollama),
/// provides type-safe tools with native Human-in-the-Loop interrupts,
/// and applies production middleware (retries, skills, tool approval).
class GenkitService {
  final Ref _ref;
  Genkit? _ai;
  final Map<String, Tool> _registeredTools = {};

  GenkitService(this._ref);

  /// Initializes or rebuilds the Genkit engine with configured model plugins.
  Genkit get ai {
    if (_ai == null) {
      _rebuildGenkit();
    }
    return _ai!;
  }

  void _rebuildGenkit() {
    final aiService = _ref.read(aiServiceProvider);
    final settings = aiService.settings;
    final plugins = <GenkitPlugin>[];

    // 1. Google Gemini Plugin
    final googleKey = settings.apiKeys['google'] ?? '';
    plugins.add(googleAI(apiKey: googleKey.isNotEmpty ? googleKey : null));

    // 2. Anthropic Plugin
    final anthropicKey = settings.apiKeys['anthropic'] ?? '';
    plugins.add(anthropic(apiKey: anthropicKey.isNotEmpty ? anthropicKey : null));

    // 3. OpenAI & Compatible Providers (Groq, DeepSeek, OpenRouter, Ollama)
    final openAiProviders = ['openai', 'deepseek', 'groq', 'openrouter', 'local_edge'];
    for (final pid in openAiProviders) {
      final key = settings.apiKeys[pid] ?? (pid == 'local_edge' ? 'ollama' : '');
      final customUrl = settings.baseUrls[pid];
      final defaultUrl = AiProviders.byId(pid).baseUrl;
      final baseUrl = (customUrl != null && customUrl.isNotEmpty) ? customUrl : defaultUrl;

      plugins.add(openAI(
        name: pid,
        apiKey: key.isNotEmpty ? key : null,
        baseUrl: baseUrl.isNotEmpty ? baseUrl : null,
      ));
    }

    // 4. Common Middleware Plugins
    plugins.add(SkillsPlugin());
    plugins.add(ToolApprovalPlugin());

    _ai = Genkit(plugins: plugins);
    _registeredTools.clear();
  }

  /// Refreshes configuration when AI settings change.
  void invalidate() {
    _ai = null;
    _registeredTools.clear();
  }

  /// Resolves the current ModelRef based on QuantumIDE's active AISettings.
  ModelRef _resolveCurrentModel() {
    final aiService = _ref.read(aiServiceProvider);
    final providerId = aiService.selectedProviderId;
    final modelName = aiService.selectedModel;

    if (providerId == 'google') {
      return googleAI.gemini(modelName);
    } else if (providerId == 'anthropic') {
      return anthropic.model(modelName);
    } else {
      // openai, deepseek, groq, openrouter, local_edge
      return openAI.model(modelName, namespace: providerId);
    }
  }

  /// Converts QuantumIDE AIToolDefinitions into Genkit Tools with Human-in-the-loop interrupts.
  List<Tool> getTools({bool readOnly = false}) {
    final executor = _ref.read(enhancedAIToolExecutorProvider);
    final definitions = executor.getTools(readAccessOnly: readOnly);

    final tools = <Tool>[];
    for (final def in definitions) {
      if (!_registeredTools.containsKey(def.name)) {
        _registeredTools[def.name] = _createGenkitTool(def, executor);
      }
      tools.add(_registeredTools[def.name]!);
    }
    return tools;
  }

  Tool _createGenkitTool(AIToolDefinition def, EnhancedAIToolExecutor executor) {
    final schema = SchemanticType.from<Map<String, dynamic>>(
      jsonSchema: def.inputSchema,
      parse: (j) => j is Map ? Map<String, dynamic>.from(j) : <String, dynamic>{},
    );

    return ai.defineTool(
      name: def.name,
      description: def.description,
      inputSchema: schema,
      fn: (input, ctx) async {
        // Human-in-the-loop: If tool requires confirmation and has not been resumed
        final needsConfirm = def.requiresConfirmation || def.risk == AIToolRisk.high;
        if (needsConfirm && ctx.resumed == null) {
          return ToolResult.interrupt({
            'name': def.name,
            'arguments': input,
            'risk': def.risk.name,
          });
        }

        // Execute the tool through QuantumIDE's EnhancedAIToolExecutor
        final toolCall = AIToolCall(
          id: const Uuid().v4(),
          name: def.name,
          arguments: input,
        );
        final result = await executor.executeTool(toolCall);
        return ToolResult.response(result.content);
      },
    );
  }

  /// Executes text and agentic generation with streaming, retries, and tool execution.
  Future<GenkitResponse> generate({
    String? prompt,
    String? system,
    List<Message>? messages,
    bool enableTools = true,
    bool readOnlyTools = false,
    void Function(String textChunk)? onStreamChunk,
  }) async {
    final model = _resolveCurrentModel();
    final tools = enableTools ? getTools(readOnly: readOnlyTools) : <Tool>[];

    // Determine workspace skills directory if present
    final workspacePath = _ref.read(workspaceProvider).currentPath ?? '';
    final skillsPath = '$workspacePath/.quantum/skills';

    try {
      final result = await ai.generate(
        model: model,
        prompt: prompt,
        system: system,
        messages: messages,
        tools: tools.isNotEmpty ? tools : null,
        onChunk: onStreamChunk != null
            ? (chunk) => onStreamChunk(chunk.text)
            : null,
        use: [
          retry(maxRetries: 3),
          skills(skillPaths: [skillsPath, 'skills']),
          toolApproval(approved: ['read_file', 'search_code', 'glob_search', 'list_directory']),
        ],
      );

      final isInterrupted = result.finishReason == FinishReason.interrupted;
      final interrupts = <GenkitInterruptInfo>[];

      if (isInterrupted) {
        for (final part in result.interrupts) {
          final metadata = part.metadata ?? {};
          final interruptData = metadata['interrupt'];
          final toolName = part.toolRequest.name;
          final args = part.toolRequest.input is Map
              ? Map<String, dynamic>.from(part.toolRequest.input as Map)
              : <String, dynamic>{};

          interrupts.add(GenkitInterruptInfo(
            requestPart: part,
            toolName: toolName,
            arguments: args,
            risk: (interruptData is Map ? interruptData['risk'] : null) ?? 'medium',
          ));
        }
      }

      final usage = result.usage;
      return GenkitResponse(
        text: result.text,
        isInterrupted: isInterrupted,
        interrupts: interrupts,
        finishReason: result.finishReason,
        promptTokens: usage?.inputTokens ?? 0,
        completionTokens: usage?.outputTokens ?? 0,
        totalTokens: usage?.totalTokens ?? 0,
        rawResult: result,
      );
    } catch (e) {
      debugPrint('Genkit generation error: $e');
      rethrow;
    }
  }

  /// Resumes an interrupted generation after user confirmation.
  Future<GenkitResponse> resumeInterrupted({
    required GenerateResult previousResult,
    required ToolRequestPart approvedPart,
    dynamic resumePayload = true,
    void Function(String textChunk)? onStreamChunk,
  }) async {
    final model = _resolveCurrentModel();

    final result = await ai.generate(
      model: model,
      messages: previousResult.messages,
      tools: getTools(),
      interruptRestart: [approvedPart],
      onChunk: onStreamChunk != null
          ? (chunk) => onStreamChunk(chunk.text)
          : null,
      use: [
        retry(maxRetries: 3),
      ],
    );

    final isInterrupted = result.finishReason == FinishReason.interrupted;
    final interrupts = <GenkitInterruptInfo>[];

    if (isInterrupted) {
      for (final part in result.interrupts) {
        final toolName = part.toolRequest.name;
        final args = part.toolRequest.input is Map
            ? Map<String, dynamic>.from(part.toolRequest.input as Map)
            : <String, dynamic>{};

        interrupts.add(GenkitInterruptInfo(
          requestPart: part,
          toolName: toolName,
          arguments: args,
          risk: 'medium',
        ));
      }
    }

    final usage = result.usage;
    return GenkitResponse(
      text: result.text,
      isInterrupted: isInterrupted,
      interrupts: interrupts,
      finishReason: result.finishReason,
      promptTokens: usage?.inputTokens ?? 0,
      completionTokens: usage?.outputTokens ?? 0,
      totalTokens: usage?.totalTokens ?? 0,
      rawResult: result,
    );
  }
}

/// Riverpod provider for GenkitService
final genkitServiceProvider = Provider<GenkitService>((ref) {
  return GenkitService(ref);
});
