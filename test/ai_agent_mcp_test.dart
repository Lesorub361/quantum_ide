import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quantum_ide/core/services/agent_toolbox.dart';
import 'package:quantum_ide/core/services/mcp_service.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/features/ai_assistant/roxum/roxum_agentic_tools.dart';
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
  });
}
