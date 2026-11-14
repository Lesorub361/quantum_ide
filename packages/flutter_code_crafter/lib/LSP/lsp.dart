import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../utils/utils.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

part 'lsp_socket.dart';
part 'lsp_stdio.dart';

sealed class LspConfig {
  /// The file path of the document to be processed by the LSP.
  final String filePath;

  /// The language ID of the language.
  ///
  /// languageId depends on the server you are using.
  /// For example, for rust-analyzer give "rust", for pyright-langserver, it is 'python' and so on.
  final String languageId;

  /// The workspace path of the document to be processed by the LSP.
  ///
  /// The workspacePath is the root directory of the project or workspace.
  /// If you are using a single file, you can set it to the parent directory of the file.
  final String workspacePath;

  /// Whether to disable warnings from the LSP server.
  final bool disableWarning;

  /// Whether to disable errors from the LSP server.
  final bool disableError;

  final StreamController<Map<String, dynamic>> _responseController =
      StreamController.broadcast();
  int _nextId = 1;
  final _openDocuments = <String, int>{};

  LspConfig({
    required this.filePath,
    required this.workspacePath,
    required this.languageId,
    this.disableWarning = false,
    this.disableError = false,
  });

  void dispose();

  Future<Map<String, dynamic>> _sendRequest({
    required String method,
    required Map<String, dynamic> params,
  });

  Future<void> _sendNotification({
    required String method,
    required Map<String, dynamic> params,
  });

  /// This method is used to initialize the LSP server.
  ///
  /// This method is used internally by the [CodeCrafter] widget and calling it directly is not recommended.
  /// It may crash the LSP server if called multiple times.
  Future<void> initialize() async {
    final workspaceUri = Uri.directory(workspacePath).toString();
    final response = await _sendRequest(
      method: 'initialize',
      params: {
        'processId': pid,
        'rootUri': workspaceUri,
        'workspaceFolders': [
          {'uri': workspaceUri, 'name': 'workspace'},
        ],
        'capabilities': {
          'textDocument': {
            'completion': {
              'completionItem': {'snippetSupport': false},
            },
          },
          'hover': {
            'contentFormat': ['markdown'],
          },
        },
      },
    );

    if (response['error'] != null) {
      throw Exception('Initialization failed: ${response['error']}');
    }

    await _sendNotification(method: 'initialized', params: {});
  }

  Map<String, dynamic> _commonParams(int line, int character) {
    return {
      'textDocument': {'uri': Uri.file(filePath).toString()},
      'position': {'line': line, 'character': character},
    };
  }

  /// Opens the document in the LSP server.
  ///
  /// This method is used internally by the [CodeCrafter] widget and calling it directly is not recommended.
  Future<void> openDocument() async {
    final version = (_openDocuments[filePath] ?? 0) + 1;
    _openDocuments[filePath] = version;
    final String text = await File(filePath).readAsString();
    await _sendNotification(
      method: 'textDocument/didOpen',
      params: {
        'textDocument': {
          'uri': Uri.file(filePath).toString(),
          'languageId': languageId,
          'version': version,
          'text': text,
        },
      },
    );
    await Future.delayed(Duration(milliseconds: 300));
  }

  Future<void> updateDocument(String content) async {
    if (!_openDocuments.containsKey(filePath)) {
      return;
    }

    final version = _openDocuments[filePath]! + 1;
    _openDocuments[filePath] = version;

    await _sendNotification(
      method: 'textDocument/didChange',
      params: {
        'textDocument': {
          'uri': Uri.file(filePath).toString(),
          'version': version,
        },
        'contentChanges': [
          {'text': content},
        ],
      },
    );
  }

  /// Updates the document in the LSP server if there is any change.
  /// ///
  /// This method is used internally by the [CodeCrafter] widget and calling it directly is not recommended.
  Future<void> closeDocument() async {
    if (!_openDocuments.containsKey(filePath)) return;

    await _sendNotification(
      method: 'textDocument/didClose',
      params: {
        'textDocument': {'uri': Uri.file(filePath).toString()},
      },
    );
    _openDocuments.remove(filePath);
  }

  /// This method is used to get completions at a specific position in the document.
  ///
  /// This method is used internally by the [CodeCrafter], calling this with appropriate parameters will returns a [List] of [LspCompletion].
  Future<List<LspCompletion>> getCompletions(int line, int character) async {
    List<LspCompletion> completion = [];
    final response = await _sendRequest(
      method: 'textDocument/completion',
      params: _commonParams(line, character),
    );
    for (var item in response['result']['items']) {
      completion.add(
        LspCompletion(
          label: item['label'],
          itemType: CompletionItemType.values.firstWhere(
            (type) => type.value == item['kind'],
            orElse: () => CompletionItemType.text,
          ),
        ),
      );
    }
    return completion;
  }

  /// This method is used to get details at a specific position in the document.
  ///
  /// This method is used internally by the [CodeCrafter], calling this with appropriate parameters will returns a [String].
  /// If the LSP server does not support hover or the location provided is invalid, it will return an empty string.
  Future<String> getHover(int line, int character) async {
    final response = await _sendRequest(
      method: 'textDocument/hover',
      params: _commonParams(line, character),
    );
    final contents = response['result']?['contents'];
    if (contents == null || contents.isEmpty) return '';
    if (contents is String) return contents;
    if (contents is Map && contents.containsKey('value')) {
      return contents['value'] ?? '';
    }
    if (contents is List && contents.isNotEmpty) {
      return contents
          .map((item) {
            if (item is String) return item;
            if (item is Map && item.containsKey('value')) return item['value'];
            return '';
          })
          .join('\n');
    }
    return '';
  }

  Future<String> getDefinition(int line, int character) async {
    final response = await _sendRequest(
      method: 'textDocument/definition',
      params: _commonParams(line, character),
    );
    if (response['result'] == null || response['result'].isEmpty) return '';
    return response['result'][1]['uri'] ?? '';
  }

  Future<List<dynamic>> getReferences(int line, int character) async {
    final params = _commonParams(line, character);
    params['context'] = {'includeDeclaration': true};
    final response = await _sendRequest(
      method: 'textDocument/references',
      params: params,
    );
    if (response['result'] == null || response['result'].isEmpty) return [];
    return response['result'];
  }

  Stream<Map<String, dynamic>> get responses => _responseController.stream;
}
