import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quantum_ide/core/services/agent_toolbox.dart';
import 'package:quantum_ide/core/services/mcp_catalog.dart';
import 'package:quantum_ide/core/services/mcp_service.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/features/ai_assistant/roxum/roxum_agentic_tools.dart';
import 'package:quantum_ide/features/ai_assistant/roxum/roxum_ai_client.dart';
import 'package:quantum_ide/features/ai_assistant/roxum/roxum_skill_loader.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MCP Service Built-in Servers & Tools', () {
    late ProviderContainer container;
    late Directory tempWorkspace;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tempWorkspace = await Directory.systemTemp.createTemp(
        'quantum_mcp_test_',
      );
      final sampleFile = File('${tempWorkspace.path}/sample.dart');
      await sampleFile.writeAsString('''
import 'dart:async';

// Reference to Calculator in comment
class Helper {
  final Calculator calc = Calculator();
}

class Calculator {
  int add(int a, int b) {
    return a + b;
  }

  int multiply(int a, int b) {
    return a * b;
  }
}
''');

      container = ProviderContainer();
      await container
          .read(workspaceProvider.notifier)
          .setWorkspace(tempWorkspace.path);
    });

    tearDown(() async {
      container.dispose();
      if (await tempWorkspace.exists()) {
        await tempWorkspace.delete(recursive: true);
      }
    });

    test('Discovers all default built-in MCP tools in parallel', () async {
      final mcpNotifier = container.read(mcpServiceProvider.notifier);
      final tools = await mcpNotifier.getAvailableMcpTools();
      final toolNames = tools.map((t) => '${t['server']}/${t['name']}').toSet();

      expect(toolNames, contains('quantum-codegraph/project_symbols'));
      expect(toolNames, contains('quantum-codegraph/read_symbol'));
      expect(toolNames, contains('quantum-codegraph/find_symbol_usages'));
      expect(toolNames, contains('quantum-codegraph/semantic_search_code'));
      expect(toolNames, contains('quantum-token-saver/smart_analyze_errors'));
      expect(toolNames, contains('quantum-token-saver/scan_todos'));
      expect(toolNames, contains('quantum-token-saver/run_tests'));
      expect(toolNames, contains('quantum-memory/save_memory'));
      expect(toolNames, contains('quantum-memory/read_memory'));
      expect(toolNames, contains('quantum-memory/delete_memory'));
      expect(toolNames, contains('quantum-web-fetch/fetch_url_markdown'));
      expect(toolNames, contains('quantum-web-fetch/web_search_docs'));
      expect(toolNames, contains('quantum-build-doctor/get_build_diagnostics'));
      expect(toolNames, contains('quantum-build-doctor/optimal_build_command'));
      expect(toolNames, contains('quantum-build-doctor/install_built_apk'));
      expect(toolNames, contains('quantum-device-qa/qa_get_runtime_errors'));
      expect(toolNames, contains('quantum-device-qa/adb_devices_and_logcat'));
      expect(
        toolNames,
        contains('quantum-device-qa/device_hardware_telemetry'),
      );
      expect(
        toolNames,
        contains('quantum-sqlite-telemetry/sqlite_inspect_schema'),
      );
      expect(toolNames, contains('quantum-sqlite-telemetry/sqlite_query'));
      expect(
        toolNames,
        contains('quantum-sqlite-telemetry/inspect_network_and_logs'),
      );
    });

    test(
      'quantum-codegraph: project_symbols, read_symbol, and find_symbol_usages',
      () async {
        final mcpNotifier = container.read(mcpServiceProvider.notifier);

        final symbolsRes = await mcpNotifier.executeMcpTool(
          'quantum-codegraph',
          'project_symbols',
          {},
        );
        expect(symbolsRes['content'].toString(), contains('Calculator'));
        expect(symbolsRes['content'].toString(), contains('Helper'));

        // read_symbol should skip comment/field reference and locate actual class declaration
        final readRes = await mcpNotifier.executeMcpTool(
          'quantum-codegraph',
          'read_symbol',
          {'filePath': 'sample.dart', 'symbolName': 'Calculator'},
        );
        expect(readRes['isError'], isNot(true));
        expect(readRes['range'], equals('#L8-16'));
        expect(readRes['content'].toString(), contains('class Calculator {'));
        expect(
          readRes['content'].toString(),
          contains('int multiply(int a, int b)'),
        );

        final usagesRes = await mcpNotifier.executeMcpTool(
          'quantum-codegraph',
          'find_symbol_usages',
          {'symbolName': 'Calculator'},
        );
        expect(usagesRes['content'].toString(), contains('sample.dart:5:'));
        expect(usagesRes['content'].toString(), contains('sample.dart:8:'));
      },
    );

    test(
      'quantum-memory: save_memory, read_memory, and delete_memory',
      () async {
        final mcpNotifier = container.read(mcpServiceProvider.notifier);

        final saveRes = await mcpNotifier.executeMcpTool(
          'quantum-memory',
          'save_memory',
          {'key': 'architecture', 'fact': 'Riverpod + GoRouter'},
        );
        expect(saveRes['content'].toString(), contains('Saved [architecture]'));

        final readRes = await mcpNotifier.executeMcpTool(
          'quantum-memory',
          'read_memory',
          {'key': 'architecture'},
        );
        expect(readRes['content'].toString(), contains('Riverpod + GoRouter'));

        final delRes = await mcpNotifier.executeMcpTool(
          'quantum-memory',
          'delete_memory',
          {'key': 'architecture'},
        );
        expect(
          delRes['content'].toString(),
          contains('Deleted [architecture]'),
        );
      },
    );
  });

  group('RoxumAgenticTools & AgentToolbox MCP Parsing', () {
    test(
      'RoxumAgenticTools caps MCP function names at <= 64 chars and formats output cleanly',
      () {
        final rawTools = [
          {
            'server': 'very_long_custom_enterprise_mcp_server_name_identifier',
            'name':
                'extremely_long_tool_function_name_that_exceeds_sixty_four_characters',
            'description': 'Test long MCP tool name',
            'inputSchema': {
              'type': 'object',
              'properties': {
                'query': {'type': 'string'},
              },
              'required': ['query'],
            },
          },
        ];

        final built = RoxumAgenticTools.buildMcpOpenAiTools(rawTools);
        expect(built, hasLength(1));
        final fn = built.first['function'] as Map<String, dynamic>;
        final safeName = fn['name'] as String;
        expect(safeName.length, lessThanOrEqualTo(64));
        expect(safeName, startsWith('mcp__'));

        final formatted = RoxumAgenticTools.formatMcpResult({
          'content': [
            {'type': 'text', 'text': 'Line 1'},
            {'type': 'text', 'text': 'Line 2'},
          ],
        });
        expect(formatted, equals('Line 1\nLine 2'));
      },
    );

    test('AgentToolbox.parse supports single/double quotes and MCP calls', () {
      const sampleOutput = '''
Let's inspect the symbols first:
<tool name="mcp" server="quantum-codegraph" tool="project_symbols">{"directory":"lib"}</tool>
And with single quotes:
<tool name='read_file' path='lib/main.dart' start='1' end='40'/>
''';
      final calls = AgentToolbox.parse(sampleOutput);
      expect(calls, hasLength(2));
      expect(calls[0].name, equals('mcp'));
      expect(calls[0].args['server'], equals('quantum-codegraph'));
      expect(calls[0].args['tool'], equals('project_symbols'));
      expect(calls[0].args['_body'], equals('{"directory":"lib"}'));
      expect(calls[1].name, equals('read_file'));
      expect(calls[1].args['path'], equals('lib/main.dart'));
    });

    test(
      'RoxumAiClient.compactMessagesForTokenSavings compacts old/superseded writeFile args',
      () {
        final bigCode1 = List.generate(
          60,
          (i) => 'final v$i = $i; // line',
        ).join('\n');
        final bigCode2 = List.generate(
          65,
          (i) => 'final u$i = $i; // updated',
        ).join('\n');
        final messages = <Map<String, dynamic>>[
          {'role': 'system', 'content': 'sys'},
          {'role': 'user', 'content': 'build game'},
          {
            'role': 'assistant',
            'content': null,
            'tool_calls': [
              {
                'id': 'call_1',
                'type': 'function',
                'function': {
                  'name': 'writeFile',
                  'arguments': jsonEncode({
                    'filePath': 'lib/main.dart',
                    'content': bigCode1,
                  }),
                },
              },
            ],
          },
          {'role': 'tool', 'tool_call_id': 'call_1', 'content': 'Wrote lib/main.dart'},
          {
            'role': 'assistant',
            'content': null,
            'tool_calls': [
              {
                'id': 'call_2',
                'type': 'function',
                'function': {
                  'name': 'writeFile',
                  'arguments': jsonEncode({
                    'filePath': 'lib/main.dart',
                    'content': bigCode2,
                  }),
                },
              },
            ],
          },
          {'role': 'tool', 'tool_call_id': 'call_2', 'content': 'Wrote lib/main.dart'},
        ];

        RoxumAiClient.compactMessagesForTokenSavings(messages);

        final firstCallArgs = jsonDecode(
          ((messages[2]['tool_calls'] as List).first as Map)['function']['arguments']
              as String,
        ) as Map<String, dynamic>;
        final latestCallArgs = jsonDecode(
          ((messages[4]['tool_calls'] as List).first as Map)['function']['arguments']
              as String,
        ) as Map<String, dynamic>;

        expect(
          firstCallArgs['content'].toString(),
          startsWith('[compacted writeFile content: 60 lines'),
        );
        expect(latestCallArgs['content'], equals(bigCode2));
      },
    );

    test(
      'McpService.formatCompactAnalyzerDiagnostics groups repeated (file, code) errors',
      () {
        final lines = <String>[
          for (var i = 0; i < 12; i++)
            "  error • The name 'Colors' is defined in the libraries 'package:flutter/material.dart' and 'package:vector_math/vector_math_64.dart' • lib/main.dart:${100 + i * 10}:5 • ambiguous_import",
          for (var i = 0; i < 6; i++)
            '  error • Evaluation of this constant expression throws an exception • lib/world.dart:${20 + i}:3 • const_with_non_const',
          '  warning • Unused import • lib/world.dart:2:8 • unused_import',
        ];
        final formatted = McpService.formatCompactAnalyzerDiagnostics(
          lines.join('\n'),
        );

        expect(formatted, contains('Summary: 18 error(s), 1 warning(s), 0 info(s)'));
        expect(formatted, contains('[12x] ambiguous_import'));
        expect(formatted, contains('[6x] const_with_non_const'));
        expect(formatted, contains('lib/world.dart:2: unused_import'));
        expect(formatted.split('\n').length, lessThanOrEqualTo(6));
      },
    );

    test(
      'McpService.formatCompactAnalyzerDiagnostics deduplicates main.dart vs lib/main.dart and keeps line numbers visible',
      () {
        final dupLines = <String>[
          "  error • Undefined name 'x' • main.dart:257:11 • undefined_identifier",
          "  error • Undefined name 'x' • main.dart:261:11 • undefined_identifier",
          "  error • Undefined name 'x' • main.dart:288:11 • undefined_identifier",
          "  error • Undefined name 'x' • main.dart:305:11 • undefined_identifier",
          "  error • Undefined name 'x' • main.dart:410:11 • undefined_identifier",
          "  error • Undefined name 'x' • lib/main.dart:257:11 • undefined_identifier",
          "  error • Undefined name 'x' • lib/main.dart:261:11 • undefined_identifier",
          "  error • Undefined name 'x' • lib/main.dart:288:11 • undefined_identifier",
          "  error • Undefined name 'x' • lib/main.dart:305:11 • undefined_identifier",
          "  error • Undefined name 'x' • lib/main.dart:410:11 • undefined_identifier",
        ];
        final formatted = McpService.formatCompactAnalyzerDiagnostics(
          dupLines.join('\n'),
        );
        expect(formatted, contains('Summary: 5 error(s)'));
        expect(formatted, contains('257, 261, 288, 305, 410'));
        expect(formatted, isNot(contains('..')));
      },
    );

    test(
      'RoxumAiClient.compactMessagesForTokenSavings preserves latest diagnostics while collapsing superseded diagnostics',
      () {
        final oldDiag = jsonEncode({
          'success': true,
          'output':
              'Summary: 29 error(s), 0 warning(s), 0 info(s).\n${List.filled(40, "error • lib/main.dart:257: undefined_identifier — Undefined name 'x'.").join('\n')}',
        });
        final latestDiag = jsonEncode({
          'success': true,
          'output':
              'Summary: 2 error(s), 0 warning(s), 0 info(s).\n${List.filled(35, "error • lib/main.dart:812: invalid_constant — Invalid constant value.").join('\n')}',
        });
        final messages = <Map<String, dynamic>>[
          {'role': 'system', 'content': 'sys'},
          {'role': 'user', 'content': 'fix game'},
          {
            'role': 'tool',
            'tool_call_id': 'diag_1',
            'name': 'getLspDiagnostics',
            'content': oldDiag,
          },
          {
            'role': 'tool',
            'tool_call_id': 'diag_2',
            'name': 'getLspDiagnostics',
            'content': latestDiag,
          },
          for (var i = 0; i < 12; i++)
            {
              'role': 'tool',
              'tool_call_id': 'read_$i',
              'name': 'readFile',
              'content': 'short read $i',
            },
        ];

        RoxumAiClient.compactMessagesForTokenSavings(messages);

        expect(
          messages[2]['content'].toString(),
          contains('[superseded diagnostics'),
        );
        // Latest diagnostics MUST remain intact even when older than 10 messages!
        expect(messages[3]['content'], equals(latestDiag));
      },
    );

    test(
      'RoxumAiClient.extractTextToolCalls parses <tool_call> and <function=...> fallback blocks',
      () {
        const sample = '''
Сейчас применю правку:
<tool_call>
{"name": "editFile", "arguments": {"filePath": "lib/main.dart", "oldText": "int i = 0;", "newText": "int x = 0;"}}
</tool_call>
''';
        final res = RoxumAiClient.extractTextToolCalls(sample);
        expect(res.calls, hasLength(1));
        expect(res.calls.first.name, equals('editFile'));
        expect(res.calls.first.args['filePath'], equals('lib/main.dart'));
        expect(res.remainingText, equals('Сейчас применю правку:'));
      },
    );

    test(
      'RoxumAgenticTools supports fuzzy editFile, multiEditFile, placeholder rejection, and gitDiff outside git',
      () async {
        SharedPreferences.setMockInitialValues({});
        final tempDir = await Directory.systemTemp.createTemp('roxum_tools_test_');
        final localContainer = ProviderContainer();
        addTearDown(() async {
          localContainer.dispose();
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });
        await localContainer
            .read(workspaceProvider.notifier)
            .setWorkspace(tempDir.path);

        final toolsProvider = Provider<RoxumAgenticTools>(
          (ref) => RoxumAgenticTools(ref, pendingEdits: {}),
        );
        final tools = localContainer.read(toolsProvider);

        final gitRes = await tools.execute('gitDiff', {'filePath': 'sample.dart'});
        expect(gitRes.success, isFalse);
        expect(gitRes.output, equals('Not a git repository.'));

        final codeLines = <String>[
          for (var i = 0; i < 40; i++) '  final line$i = $i;',
        ].join('\n');
        await File('${tempDir.path}/game.dart').writeAsString(
          'class Game {\n$codeLines\n  void tick() {\n    int i = 0;\n  }\n}\n',
        );

        // Reject destructive lazy placeholder overwrite
        final lazyWrite = await tools.execute('writeFile', {
          'filePath': 'game.dart',
          'content': 'class Game {\n  // ... existing code ...\n}\n',
        });
        expect(lazyWrite.success, isFalse);
        expect(lazyWrite.output, contains('REJECTED'));

        // Fuzzy indentation-tolerant editFile + multiEditFile
        final multiRes = await tools.execute('multiEditFile', {
          'filePath': 'game.dart',
          'edits': [
            {
              'oldText': 'final line0 = 0;',
              'newText': '  final line0 = 100;',
            },
            {
              'oldText': 'void tick() {\n  int i = 0;\n}',
              'newText': '  void tick() {\n    int x = 1;\n  }',
            },
          ],
        });
        expect(multiRes.success, isTrue);
        final updatedDisk = await File('${tempDir.path}/game.dart').readAsString();
        expect(updatedDisk, contains('final line0 = 100;'));
        expect(updatedDisk, contains('int x = 1;'));
      },
    );

    test('Official Dart & Flutter MCP (dart mcp-server) preset is registered', () {
      final catalogItem = McpCatalog.items.where(
        (i) => i.id == 'dart-flutter-mcp',
      );
      expect(catalogItem, isNotEmpty);
      expect(catalogItem.first.command, equals('dart'));
      expect(catalogItem.first.args, equals(['mcp-server']));

      final preset = McpService.topPresets().where(
        (p) => p.config.name == 'dart-flutter-mcp',
      );
      expect(preset, isNotEmpty);
      expect(preset.first.config.command, equals('dart'));
      expect(preset.first.config.args, equals(['mcp-server']));
    });

    test(
      'RoxumSkillLoader loads workspace SKILL.md and matches built-in Flutter/Genkit skills on demand',
      () async {
        final tempSkillWs = await Directory.systemTemp.createTemp('roxum_skill_test_');
        addTearDown(() async {
          if (await tempSkillWs.exists()) {
            await tempSkillWs.delete(recursive: true);
          }
        });
        final skillDir = Directory('${tempSkillWs.path}/.agents/skills/custom-game');
        await skillDir.create(recursive: true);
        await File('${skillDir.path}/SKILL.md').writeAsString('''
---
name: Custom Game Loop
description: Rules for 60fps Flame game loop
---
Always use fixed timestep for physics updates.
''');

        final matchedCustom = RoxumSkillLoader.buildMatchedSkillsBlock(
          workspace: tempSkillWs.path,
          userPrompt: 'Помоги оптимизировать custom game loop',
        );
        expect(matchedCustom, contains('Custom Game Loop'));
        expect(matchedCustom, contains('fixed timestep'));

        final matchedPreview = RoxumSkillLoader.buildMatchedSkillsBlock(
          workspace: tempSkillWs.path,
          userPrompt: 'Добавь @Preview для моей кнопки',
          activeFilePath: 'lib/widgets/my_button.dart',
        );
        expect(matchedPreview, contains('Flutter Widget Previews (@Preview)'));
        expect(matchedPreview, contains('package:flutter/widget_previews.dart'));
      },
    );
  });
}
