import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_editor/re_editor.dart';

class Snippet {
  final String prefix;
  final String name;
  final String description;
  final String body;
  final String language;

  const Snippet({
    required this.prefix,
    required this.name,
    required this.description,
    required this.body,
    required this.language,
  });
}

class SnippetsService {
  List<Snippet> getSnippetsForLanguage(String language) {
    return _snippets.where((s) => s.language == language).toList();
  }

  List<Snippet> search(String query) {
    if (query.isEmpty) return _snippets;
    final lower = query.toLowerCase();
    return _snippets.where((s) =>
      s.prefix.toLowerCase().contains(lower) ||
      s.name.toLowerCase().contains(lower) ||
      s.description.toLowerCase().contains(lower)
    ).toList();
  }

  void insertSnippet(CodeLineEditingController controller, Snippet snippet) {
    controller.replaceSelection(snippet.body);
  }

  static final List<Snippet> _snippets = [
    const Snippet(
      prefix: 'stless',
      name: 'StatelessWidget',
      description: 'Create a StatelessWidget',
      language: 'dart',
      body: 'class MyWidget extends StatelessWidget {\n  const MyWidget({super.key});\n\n  @override\n  Widget build(BuildContext context) {\n    return Container(\n      // TODO\n    );\n  }\n}',
    ),
    const Snippet(
      prefix: 'stful',
      name: 'StatefulWidget',
      description: 'Create a StatefulWidget',
      language: 'dart',
      body: 'class MyWidget extends StatefulWidget {\n  const MyWidget({super.key});\n\n  @override\n  State<MyWidget> createState() => _MyWidgetState();\n}\n\nclass _MyWidgetState extends State<MyWidget> {\n  @override\n  Widget build(BuildContext context) {\n    return Container(\n      // TODO\n    );\n  }\n}',
    ),
    const Snippet(
      prefix: 'stlessp',
      name: 'ConsumerWidget',
      description: 'StatelessWidget with Provider',
      language: 'dart',
      body: 'class MyWidget extends ConsumerWidget {\n  const MyWidget({super.key});\n\n  @override\n  Widget build(BuildContext context, WidgetRef ref) {\n    return Container(\n      // TODO\n    );\n  }\n}',
    ),
    const Snippet(
      prefix: 'stfulp',
      name: 'ConsumerStatefulWidget',
      description: 'StatefulWidget with Provider',
      language: 'dart',
      body: 'class MyWidget extends ConsumerStatefulWidget {\n  const MyWidget({super.key});\n\n  @override\n  ConsumerState<MyWidget> createState() => _MyWidgetState();\n}\n\nclass _MyWidgetState extends ConsumerState<MyWidget> {\n  @override\n  Widget build(BuildContext context) {\n    return Container(\n      // TODO\n    );\n  }\n}',
    ),
    const Snippet(
      prefix: 'column',
      name: 'Column',
      description: 'Column with children',
      language: 'dart',
      body: 'Column(\n  crossAxisAlignment: CrossAxisAlignment.stretch,\n  children: [\n    // TODO\n  ],\n)',
    ),
    const Snippet(
      prefix: 'row',
      name: 'Row',
      description: 'Row with children',
      language: 'dart',
      body: 'Row(\n  children: [\n    // TODO\n  ],\n)',
    ),
    const Snippet(
      prefix: 'sized',
      name: 'SizedBox',
      description: 'SizedBox with dimensions',
      language: 'dart',
      body: 'SizedBox(\n  width: 100,\n  height: 100,\n  child: Container(),\n)',
    ),
    const Snippet(
      prefix: 'padding',
      name: 'Padding',
      description: 'Padding widget',
      language: 'dart',
      body: 'Padding(\n  padding: const EdgeInsets.all(16),\n  child: Container(),\n)',
    ),
    const Snippet(
      prefix: 'container',
      name: 'Container',
      description: 'Container with decoration',
      language: 'dart',
      body: 'Container(\n  padding: const EdgeInsets.all(16),\n  decoration: BoxDecoration(\n    color: Colors.white,\n    borderRadius: BorderRadius.circular(12),\n  ),\n  child: Container(),\n)',
    ),
    const Snippet(
      prefix: 'provider',
      name: 'StateProvider',
      description: 'Riverpod StateProvider',
      language: 'dart',
      body: 'final myProvider = StateProvider<String>((ref) => \'\');',
    ),
    const Snippet(
      prefix: 'notifier',
      name: 'StateNotifier',
      description: 'Riverpod StateNotifier',
      language: 'dart',
      body: 'class MyNotifier extends StateNotifier<String> {\n  MyNotifier() : super(\'\');\n\n  // TODO\n}',
    ),
    const Snippet(
      prefix: 'futureprovider',
      name: 'FutureProvider',
      description: 'Riverpod FutureProvider',
      language: 'dart',
      body: 'final myProvider = FutureProvider<String>((ref) async {\n  // TODO\n});',
    ),
    const Snippet(
      prefix: 'async',
      name: 'Async',
      description: 'Async function',
      language: 'dart',
      body: 'Future<void> myFunction() async {\n  // TODO\n}',
    ),
    const Snippet(
      prefix: 'try',
      name: 'Try-Catch',
      description: 'Try-catch block',
      language: 'dart',
      body: 'try {\n  // TODO\n} catch (e) {\n  // Handle error\n}',
    ),
    const Snippet(
      prefix: 'push',
      name: 'Navigator.push',
      description: 'Push a new route',
      language: 'dart',
      body: 'Navigator.push(\n  context,\n  MaterialPageRoute(\n    builder: (context) => DestinationPage(),\n  ),\n);',
    ),
    const Snippet(
      prefix: 'text',
      name: 'Text',
      description: 'Text widget with style',
      language: 'dart',
      body: 'Text(\n  \'Hello\',\n  style: GoogleFonts.inter(\n    fontSize: 14,\n    fontWeight: FontWeight.w600,\n    color: Colors.white,\n  ),\n)',
    ),
    const Snippet(
      prefix: 'btn',
      name: 'ElevatedButton',
      description: 'Elevated button',
      language: 'dart',
      body: 'ElevatedButton(\n  onPressed: () {},\n  style: ElevatedButton.styleFrom(\n    backgroundColor: Colors.cyanAccent,\n    shape: RoundedRectangleBorder(\n      borderRadius: BorderRadius.circular(10),\n    ),\n  ),\n  child: const Text(\'Button\'),\n)',
    ),
    const Snippet(
      prefix: 'model',
      name: 'Data Model',
      description: 'Dart data model class',
      language: 'dart',
      body: 'class ModelName {\n  final String id;\n\n  const ModelName({required this.id});\n\n  factory ModelName.fromJson(Map<String, dynamic> json) {\n    return ModelName(\n      id: json[\'id\'],\n    );\n  }\n\n  Map<String, dynamic> toJson() => {\n    \'id\': id,\n  };\n}',
    ),
    const Snippet(
      prefix: 'test',
      name: 'Test',
      description: 'Flutter test case',
      language: 'dart',
      body: 'test(\'test name\', () {\n  // TODO\n});',
    ),
    const Snippet(
      prefix: 'testwidget',
      name: 'Widget Test',
      description: 'Flutter widget test',
      language: 'dart',
      body: 'testWidgets(\'test name\', (tester) async {\n  await tester.pumpWidget(\n    const MaterialApp(\n      home: MyWidget(),\n    ),\n  );\n  // TODO\n});',
    ),
  ];
}

final snippetsServiceProvider = Provider<SnippetsService>((ref) {
  return SnippetsService();
});
