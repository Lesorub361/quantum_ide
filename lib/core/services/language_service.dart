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
      name: 'Dart',
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
      ],
      snippets: [
        CodeSnippet(
          label: 'stless',
          snippet: 'class NewWidget extends StatelessWidget {\n  const NewWidget({super.key});\n\n  @override\n  Widget build(BuildContext context) {\n    return Container();\n  }\n}',
          description: 'Stateless Widget',
          selection: TextSelection.collapsed(offset: 6),
        ),
        CodeSnippet(
          label: 'stful',
          snippet: 'class NewWidget extends StatefulWidget {\n  const NewWidget({super.key});\n\n  @override\n  State<NewWidget> createState() => _NewWidgetState();\n}\n\nclass _NewWidgetState extends State<NewWidget> {\n  @override\n  Widget build(BuildContext context) {\n    return Container();\n  }\n}',
          description: 'Stateful Widget',
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
        CodeSnippet(
          label: 'clg',
          snippet: 'console.log();',
          description: 'Console Log',
          selection: TextSelection.collapsed(offset: 12),
        ),
        CodeSnippet(
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
        CodeSnippet(
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
        CodeSnippet(
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
        CodeSnippet(
          label: 'psvm',
          snippet: 'public static void main(String[] args) {\n  \n}',
          description: 'Main Method',
          selection: TextSelection.collapsed(offset: 43),
        ),
        CodeSnippet(
          label: 'sout',
          snippet: 'System.out.println();',
          description: 'System Out Println',
          selection: TextSelection.collapsed(offset: 19),
        ),
        CodeSnippet(
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
        CodeSnippet(
          label: 'main',
          snippet: 'fun main(args: Array<String>) {\n  \n}',
          description: 'Main Function',
          selection: TextSelection.collapsed(offset: 33),
        ),
        CodeSnippet(
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
        CodeSnippet(
          label: 'def',
          snippet: 'def name():\n    pass',
          description: 'Function Definition',
          selection: TextSelection.collapsed(offset: 4),
        ),
        CodeSnippet(
          label: 'main',
          snippet: 'if __name__ == "__main__":\n    main()',
          description: 'Main Block',
          selection: TextSelection.collapsed(offset: 35),
        ),
        CodeSnippet(
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
        CodeSnippet(
          label: 'php',
          snippet: '<?php\n\n?>',
          description: 'PHP Tag',
          selection: TextSelection.collapsed(offset: 6),
        ),
        CodeSnippet(
          label: 'echo',
          snippet: 'echo "";',
          description: 'Echo Statement',
          selection: TextSelection.collapsed(offset: 6),
        ),
        CodeSnippet(
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
        CodeSnippet(
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
