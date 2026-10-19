import 'package:flutter/material.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:re_highlight/languages/all.dart';

class CodeSnippet {
  final String label;
  final String snippet;
  final String description;
  final TextSelection selection;

  const CodeSnippet({
    required this.label,
    required this.snippet,
    required this.description,
    required this.selection,
  });
}

class LanguageConfig {
  final String name;
  final List<String> extensions;
  final List<String> keywords;
  final List<CodeSnippet> snippets;
  final Mode? highlightMode;

  const LanguageConfig({
    required this.name,
    required this.extensions,
    required this.keywords,
    this.snippets = const [],
    this.highlightMode,
  });
}

class LanguageService {
  static final Map<String, LanguageConfig> _configs = {
    'dart': LanguageConfig(
      name: 'Dart & Flutter',
      extensions: ['dart'],
      highlightMode: builtinAllLanguages['dart'],
      keywords: [
        'abstract', 'as', 'assert', 'async', 'await', 'break', 'case', 'catch',
        'class', 'const', 'continue', 'covariant', 'default', 'deferred', 'do',
        'dynamic', 'else', 'enum', 'export', 'extends', 'extension', 'external',
        'factory', 'false', 'final', 'finally', 'for', 'Function', 'get', 'hide',
        'if', 'implements', 'import', 'in', 'interface', 'is', 'late', 'library',
        'mixin', 'new', 'null', 'on', 'operator', 'part', 'required', 'rethrow',
        'return', 'set', 'show', 'static', 'super', 'switch', 'sync', 'this',
        'throw', 'true', 'try', 'typedef', 'var', 'void', 'while', 'with', 'yield',
        'String', 'int', 'double', 'bool', 'List', 'Map', 'Set', 'Future', 'Stream',
        // Flutter types & widgets
        'Widget', 'BuildContext', 'State', 'StatelessWidget', 'StatefulWidget',
        'Scaffold', 'AppBar', 'Container', 'Column', 'Row', 'Text', 'Icon', 'Icons',
        'Colors', 'Padding', 'Center', 'SizedBox', 'Expanded', 'ListView', 'Card',
        'ElevatedButton', 'TextButton', 'IconButton', 'TextField', 'TextEditingController',
        'Navigator', 'MaterialPageRoute', 'Theme', 'ThemeData', 'EdgeInsets', 'BorderRadius',
        'BoxDecoration', 'TextStyle', 'FontWeight', 'CrossAxisAlignment', 'MainAxisAlignment',
        'ConsumerWidget', 'ConsumerStatefulWidget', 'ConsumerState', 'WidgetRef', 'ref',
        'setState', 'initState', 'dispose', 'didChangeDependencies', 'mounted', 'context',
        'SingleChildScrollView', 'Stack', 'Positioned', 'Wrap', 'Flexible', 'Spacer',
        'Divider', 'CircularProgressIndicator', 'LinearProgressIndicator', 'SnackBar',
        'ScaffoldMessenger', 'AlertDialog', 'Dialog', 'showDialog', 'showModalBottomSheet',
      ],
      snippets: [
        const CodeSnippet(
          label: 'stless',
          snippet: 'class NewWidget extends StatelessWidget {\n  const NewWidget({super.key});\n\n  @override\n  Widget build(BuildContext context) {\n    return Container();\n  }\n}',
          description: 'Flutter StatelessWidget',
          selection: TextSelection.collapsed(offset: 6),
        ),
        const CodeSnippet(
          label: 'stful',
          snippet: 'class NewWidget extends StatefulWidget {\n  const NewWidget({super.key});\n\n  @override\n  State<NewWidget> createState() => _NewWidgetState();\n}\n\nclass _NewWidgetState extends State<NewWidget> {\n  @override\n  Widget build(BuildContext context) {\n    return Container();\n  }\n}',
          description: 'Flutter StatefulWidget',
          selection: TextSelection.collapsed(offset: 6),
        ),
        const CodeSnippet(
          label: 'scaffold',
          snippet: 'Scaffold(\n  appBar: AppBar(\n    title: const Text(\'Title\'),\n  ),\n  body: const Center(\n    child: Text(\'Hello Quantum\'),\n  ),\n)',
          description: 'Scaffold with AppBar & Body',
          selection: TextSelection.collapsed(offset: 38),
        ),
        const CodeSnippet(
          label: 'column',
          snippet: 'Column(\n  mainAxisAlignment: MainAxisAlignment.center,\n  crossAxisAlignment: CrossAxisAlignment.center,\n  children: [\n    \n  ],\n)',
          description: 'Column with children',
          selection: TextSelection.collapsed(offset: 96),
        ),
        const CodeSnippet(
          label: 'row',
          snippet: 'Row(\n  mainAxisAlignment: MainAxisAlignment.start,\n  crossAxisAlignment: CrossAxisAlignment.center,\n  children: [\n    \n  ],\n)',
          description: 'Row with children',
          selection: TextSelection.collapsed(offset: 94),
        ),
        const CodeSnippet(
          label: 'container',
          snippet: 'Container(\n  padding: const EdgeInsets.all(12),\n  decoration: BoxDecoration(\n    color: Colors.white10,\n    borderRadius: BorderRadius.circular(8),\n  ),\n  child: const Text(\'Content\'),\n)',
          description: 'Container with padding and decoration',
          selection: TextSelection.collapsed(offset: 147),
        ),
        const CodeSnippet(
          label: 'lvb',
          snippet: 'ListView.builder(\n  itemCount: items.length,\n  itemBuilder: (context, index) {\n    return ListTile(\n      title: Text(items[index]),\n    );\n  },\n)',
          description: 'ListView.builder',
          selection: TextSelection.collapsed(offset: 25),
        ),
        const CodeSnippet(
          label: 'inkwell',
          snippet: 'InkWell(\n  borderRadius: BorderRadius.circular(8),\n  onTap: () {\n    \n  },\n  child: Container(),\n)',
          description: 'InkWell with onTap',
          selection: TextSelection.collapsed(offset: 64),
        ),
        const CodeSnippet(
          label: 'btn',
          snippet: 'ElevatedButton.icon(\n  onPressed: () {\n    \n  },\n  icon: const Icon(Icons.check, size: 16),\n  label: const Text(\'Submit\'),\n)',
          description: 'ElevatedButton.icon',
          selection: TextSelection.collapsed(offset: 37),
        ),
        const CodeSnippet(
          label: 'initstate',
          snippet: '@override\nvoid initState() {\n  super.initState();\n  \n}',
          description: 'initState lifecycle method',
          selection: TextSelection.collapsed(offset: 44),
        ),
        const CodeSnippet(
          label: 'dispose',
          snippet: '@override\nvoid dispose() {\n  \n  super.dispose();\n}',
          description: 'dispose lifecycle method',
          selection: TextSelection.collapsed(offset: 21),
        ),
        const CodeSnippet(
          label: 'build',
          snippet: '@override\nWidget build(BuildContext context) {\n  return Container();\n}',
          description: 'Widget build method',
          selection: TextSelection.collapsed(offset: 56),
        ),
        const CodeSnippet(
          label: 'setstate',
          snippet: 'setState(() {\n  \n});',
          description: 'setState callback',
          selection: TextSelection.collapsed(offset: 15),
        ),
        const CodeSnippet(
          label: 'futurebuilder',
          snippet: 'FutureBuilder<T>(\n  future: myFuture,\n  builder: (context, snapshot) {\n    if (snapshot.connectionState == ConnectionState.waiting) {\n      return const Center(child: CircularProgressIndicator());\n    }\n    if (snapshot.hasError) {\n      return Center(child: Text(\'Error: \${snapshot.error}\'));\n    }\n    final data = snapshot.data;\n    return Container();\n  },\n)',
          description: 'FutureBuilder with loading/error handling',
          selection: TextSelection.collapsed(offset: 14),
        ),
        const CodeSnippet(
          label: 'streambuilder',
          snippet: 'StreamBuilder<T>(\n  stream: myStream,\n  builder: (context, snapshot) {\n    if (snapshot.hasData) {\n      return Container();\n    }\n    return const Center(child: CircularProgressIndicator());\n  },\n)',
          description: 'StreamBuilder',
          selection: TextSelection.collapsed(offset: 14),
        ),
        const CodeSnippet(
          label: 'consumer',
          snippet: 'Consumer(\n  builder: (context, ref, child) {\n    return Container();\n  },\n)',
          description: 'Riverpod Consumer widget',
          selection: TextSelection.collapsed(offset: 55),
        ),
        const CodeSnippet(
          label: 'consumerstful',
          snippet: 'class NewWidget extends ConsumerStatefulWidget {\n  const NewWidget({super.key});\n\n  @override\n  ConsumerState<NewWidget> createState() => _NewWidgetState();\n}\n\nclass _NewWidgetState extends ConsumerState<NewWidget> {\n  @override\n  Widget build(BuildContext context) {\n    return Container();\n  }\n}',
          description: 'Riverpod ConsumerStatefulWidget',
          selection: TextSelection.collapsed(offset: 6),
        ),
      ],
    ),
    'javascript': LanguageConfig(
      name: 'JavaScript & TypeScript',
      extensions: ['js', 'mjs', 'cjs', 'ts', 'tsx', 'jsx'],
      highlightMode: builtinAllLanguages['javascript'],
      keywords: [
        'async', 'await', 'break', 'case', 'catch', 'class', 'const', 'continue',
        'debugger', 'default', 'delete', 'do', 'else', 'enum', 'export', 'extends',
        'false', 'finally', 'for', 'function', 'if', 'import', 'in', 'instanceof',
        'new', 'null', 'return', 'super', 'switch', 'this', 'throw', 'true', 'try',
        'typeof', 'var', 'void', 'while', 'with', 'yield', 'let', 'static', 'of',
      ],
      snippets: [
        const CodeSnippet(
          label: 'clg',
          snippet: 'console.log();',
          description: 'Console Log',
          selection: TextSelection.collapsed(offset: 12),
        ),
        const CodeSnippet(
          label: 'afn',
          snippet: 'const name = () => {\n  \n};',
          description: 'Arrow Function',
          selection: TextSelection.collapsed(offset: 6),
        ),
      ],
    ),
    'html': LanguageConfig(
      name: 'HTML',
      extensions: ['html', 'htm'],
      highlightMode: builtinAllLanguages['xml'],
      keywords: [
        'div', 'span', 'a', 'p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'ul', 'li',
        'ol', 'script', 'link', 'meta', 'head', 'body', 'html', 'img', 'button',
        'input', 'form', 'label', 'table', 'tr', 'td', 'th', 'thead', 'tbody',
      ],
      snippets: [
        const CodeSnippet(
          label: 'html5',
          snippet: '<!DOCTYPE html>\n<html>\n<head>\n  <title></title>\n</head>\n<body>\n\n</body>\n</html>',
          description: 'HTML5 Boilerplate',
          selection: TextSelection.collapsed(offset: 35),
        ),
      ],
    ),
    'css': LanguageConfig(
      name: 'CSS',
      extensions: ['css'],
      highlightMode: builtinAllLanguages['css'],
      keywords: [
        'background', 'border', 'color', 'display', 'font', 'height', 'margin',
        'padding', 'position', 'width', 'flex', 'grid', 'center', 'absolute',
        'relative', 'fixed', 'sticky', 'none', 'block', 'inline', 'inline-block',
      ],
      snippets: [
        const CodeSnippet(
          label: 'flex',
          snippet: 'display: flex;\njustify-content: center;\nalign-items: center;',
          description: 'Flexbox Center',
          selection: TextSelection.collapsed(offset: 14),
        ),
      ],
    ),
    'java': LanguageConfig(
      name: 'Java',
      extensions: ['java'],
      highlightMode: builtinAllLanguages['java'],
      keywords: [
        'abstract', 'assert', 'boolean', 'break', 'byte', 'case', 'catch', 'char',
        'class', 'const', 'continue', 'default', 'do', 'double', 'else', 'enum',
        'extends', 'final', 'finally', 'float', 'for', 'goto', 'if', 'implements',
        'import', 'instanceof', 'int', 'interface', 'long', 'native', 'new', 'package',
        'private', 'protected', 'public', 'return', 'short', 'static', 'strictfp',
        'super', 'switch', 'synchronized', 'this', 'throw', 'throws', 'transient',
        'try', 'void', 'volatile', 'while', 'true', 'false', 'null',
        'String', 'System', 'out', 'println', 'print', 'Object', 'Integer', 'Double',
        'Float', 'Long', 'Boolean', 'Character', 'Byte', 'Short', 'List', 'ArrayList',
        'Map', 'HashMap', 'Set', 'HashSet', 'Override',
      ],
      snippets: [
        const CodeSnippet(
          label: 'psvm',
          snippet: 'public static void main(String[] args) {\n  \n}',
          description: 'Main Method',
          selection: TextSelection.collapsed(offset: 43),
        ),
        const CodeSnippet(
          label: 'sout',
          snippet: 'System.out.println();',
          description: 'System Out Println',
          selection: TextSelection.collapsed(offset: 19),
        ),
        const CodeSnippet(
          label: 'class',
          snippet: 'public class MyClass {\n  \n}',
          description: 'Java Class',
          selection: TextSelection.collapsed(offset: 13),
        ),
      ],
    ),
    'kotlin': LanguageConfig(
      name: 'Kotlin',
      extensions: ['kt', 'kts'],
      highlightMode: builtinAllLanguages['kotlin'],
      keywords: [
        'as', 'as?', 'break', 'class', 'continue', 'do', 'else', 'false', 'for',
        'fun', 'if', 'in', '!in', 'is', '!is', 'null', 'object', 'package', 'return',
        'super', 'this', 'throw', 'true', 'try', 'typealias', 'typeof', 'val', 'var',
        'when', 'while', 'by', 'constructor', 'delegate', 'dynamic', 'field', 'file',
        'get', 'init', 'import', 'param', 'property', 'receiver', 'set', 'setparam',
        'value', 'where', 'actual', 'abstract', 'annotation', 'companion', 'const',
        'crossinline', 'data', 'enum', 'expect', 'external', 'final', 'infix', 'inline',
        'inner', 'internal', 'lateinit', 'noinline', 'open', 'operator', 'out', 'override',
        'private', 'protected', 'public', 'reified', 'sealed', 'suspend', 'tailrec', 'vararg',
        'String', 'Int', 'Double', 'Float', 'Long', 'Boolean', 'Char', 'Byte', 'Short',
        'List', 'ArrayList', 'Map', 'HashMap', 'Set', 'HashSet', 'println', 'print',
      ],
      snippets: [
        const CodeSnippet(
          label: 'main',
          snippet: 'fun main(args: Array<String>) {\n  \n}',
          description: 'Main Function',
          selection: TextSelection.collapsed(offset: 33),
        ),
        const CodeSnippet(
          label: 'sout',
          snippet: 'println()',
          description: 'Println',
          selection: TextSelection.collapsed(offset: 8),
        ),
      ],
    ),
    'python': LanguageConfig(
      name: 'Python',
      extensions: ['py', 'pyw'],
      highlightMode: builtinAllLanguages['python'],
      keywords: [
        'False', 'None', 'True', 'and', 'as', 'assert', 'async', 'await', 'break',
        'class', 'continue', 'def', 'del', 'elif', 'else', 'except', 'finally',
        'for', 'from', 'global', 'if', 'import', 'in', 'is', 'lambda', 'nonlocal',
        'not', 'or', 'pass', 'raise', 'return', 'try', 'while', 'with', 'yield',
        'print', 'len', 'range', 'str', 'int', 'float', 'list', 'dict', 'set', 'tuple',
      ],
      snippets: [
        const CodeSnippet(
          label: 'def',
          snippet: 'def name():\n    pass',
          description: 'Function Definition',
          selection: TextSelection.collapsed(offset: 4),
        ),
        const CodeSnippet(
          label: 'main',
          snippet: 'if __name__ == "__main__":\n    main()',
          description: 'Main Block',
          selection: TextSelection.collapsed(offset: 35),
        ),
        const CodeSnippet(
          label: 'class',
          snippet: 'class MyClass:\n    def __init__(self):\n        pass',
          description: 'Class Definition',
          selection: TextSelection.collapsed(offset: 6),
        ),
      ],
    ),
    'php': LanguageConfig(
      name: 'PHP',
      extensions: ['php', 'phtml'],
      highlightMode: builtinAllLanguages['php'],
      keywords: [
        'abstract', 'and', 'array', 'as', 'break', 'callable', 'case', 'catch',
        'class', 'clone', 'const', 'continue', 'declare', 'default', 'die', 'do',
        'echo', 'else', 'elseif', 'empty', 'enddeclare', 'endfor', 'endforeach',
        'endif', 'endswitch', 'endwhile', 'eval', 'exit', 'extends', 'final',
        'finally', 'fn', 'for', 'foreach', 'function', 'global', 'goto', 'if',
        'implements', 'include', 'include_once', 'instanceof', 'insteadof',
        'interface', 'isset', 'list', 'match', 'namespace', 'new', 'or', 'print',
        'private', 'protected', 'public', 'readonly', 'require', 'require_once',
        'return', 'static', 'switch', 'throw', 'trait', 'try', 'unset', 'use',
        'var', 'while', 'xor', 'yield',
      ],
      snippets: [
        const CodeSnippet(
          label: 'php',
          snippet: '<?php\n\n?>',
          description: 'PHP Tag',
          selection: TextSelection.collapsed(offset: 6),
        ),
        const CodeSnippet(
          label: 'echo',
          snippet: 'echo "";',
          description: 'Echo Statement',
          selection: TextSelection.collapsed(offset: 6),
        ),
        const CodeSnippet(
          label: 'fun',
          snippet: 'function name() {\n  \n}',
          description: 'Function',
          selection: TextSelection.collapsed(offset: 9),
        ),
      ],
    ),
    'vue': LanguageConfig(
      name: 'Vue',
      extensions: ['vue'],
      highlightMode: builtinAllLanguages['xml'],
      keywords: [
        'template', 'script', 'style', 'setup', 'scoped', 'ref', 'computed',
        'watch', 'onMounted', 'props', 'emit', 'v-if', 'v-for', 'v-model',
        'v-on', 'v-bind',
      ],
      snippets: [
        const CodeSnippet(
          label: 'vue3',
          snippet: '<script setup>\nimport { ref } from \'vue\'\n</script>\n\n<template>\n  <div>\n    \n  </div>\n</template>\n\n<style scoped>\n</style>',
          description: 'Vue 3 SFC Boilerplate',
          selection: TextSelection.collapsed(offset: 65),
        ),
      ],
    ),
  };

  static LanguageConfig? getConfigForExtension(String ext) {
    for (final config in _configs.values) {
      if (config.extensions.contains(ext)) return config;
    }
    return null;
  }

  static LanguageConfig? getConfigForFile(String path) {
    final ext = path.split('.').last.toLowerCase();
    return getConfigForExtension(ext);
  }
}
