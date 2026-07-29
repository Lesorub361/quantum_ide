import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

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

  Map<String, dynamic> toJson() => {
        'prefix': prefix,
        'name': name,
        'description': description,
        'body': body,
        'language': language,
      };

  factory Snippet.fromJson(Map<String, dynamic> json) => Snippet(
        prefix: json['prefix'] as String? ?? '',
        name: json['name'] as String? ?? '',
        description: json['description'] as String? ?? '',
        body: json['body'] as String? ?? '',
        language: json['language'] as String? ?? '',
      );
}

class SnippetsManagerService extends ChangeNotifier {
  List<Snippet> _snippets = [];
  String? _workspacePath;

  List<Snippet> get snippets => List.unmodifiable(_snippets);

  static const List<Snippet> _builtInDartSnippets = [
    Snippet(
      prefix: 'stless',
      name: 'StatelessWidget',
      description: 'StatelessWidget boilerplate',
      language: 'dart',
      body: '''class MyWidget extends StatelessWidget {
  const MyWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Container();
  }
}''',
    ),
    Snippet(
      prefix: 'stful',
      name: 'StatefulWidget',
      description: 'StatefulWidget boilerplate',
      language: 'dart',
      body: '''class MyWidget extends StatefulWidget {
  const MyWidget({super.key});

  @override
  State<MyWidget> createState() => _MyWidgetState();
}

class _MyWidgetState extends State<MyWidget> {
  @override
  Widget build(BuildContext context) {
    return Container();
  }
}''',
    ),
    Snippet(
      prefix: 'main',
      name: 'Main Function',
      description: 'Dart main function',
      language: 'dart',
      body: '''void main() {

}''',
    ),
  ];

  void setWorkspace(String path) {
    _workspacePath = path;
    loadSnippets();
  }

  Future<void> loadSnippets() async {
    _snippets = List.from(_builtInDartSnippets);

    if (_workspacePath == null) return;

    final snippetsFile = File(p.join(_workspacePath!, '.quantum', 'snippets.json'));
    if (await snippetsFile.exists()) {
      try {
        final content = await snippetsFile.readAsString();
        final List<dynamic> jsonList = json.decode(content);
        final userSnippets = jsonList
            .map((json) => Snippet.fromJson(json as Map<String, dynamic>))
            .toList();
        _snippets.addAll(userSnippets);
      } catch (_) {}
    }

    notifyListeners();
  }

  Future<void> saveSnippets() async {
    if (_workspacePath == null) return;

    final dir = Directory(p.join(_workspacePath!, '.quantum'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final userSnippets = _snippets
        .where((s) => !_builtInDartSnippets.any((b) => b.prefix == s.prefix && b.language == s.language))
        .toList();

    final snippetsFile = File(p.join(_workspacePath!, '.quantum', 'snippets.json'));
    final jsonList = userSnippets.map((s) => s.toJson()).toList();
    await snippetsFile.writeAsString(json.encode(jsonList));
  }

  List<Snippet> search(String prefix) {
    if (prefix.isEmpty) return _snippets;
    final lower = prefix.toLowerCase();
    return _snippets
        .where((s) =>
            s.prefix.toLowerCase().contains(lower) ||
            s.name.toLowerCase().contains(lower) ||
            s.description.toLowerCase().contains(lower))
        .toList();
  }

  List<Snippet> getByLanguage(String language) {
    return _snippets.where((s) => s.language == language).toList();
  }

  void addSnippet(Snippet snippet) {
    _snippets.add(snippet);
    notifyListeners();
    saveSnippets();
  }

  void updateSnippet(int index, Snippet snippet) {
    if (index >= 0 && index < _snippets.length) {
      _snippets[index] = snippet;
      notifyListeners();
      saveSnippets();
    }
  }

  void deleteSnippet(int index) {
    if (index >= 0 && index < _snippets.length) {
      _snippets.removeAt(index);
      notifyListeners();
      saveSnippets();
    }
  }
}

final snippetsManagerProvider = ChangeNotifierProvider<SnippetsManagerService>((ref) {
  return SnippetsManagerService();
});
