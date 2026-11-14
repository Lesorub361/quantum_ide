part of 'lsp.dart';

/// Callback-based [LspConfig] bridge so host IDEs (like QuantumIDE) can connect
/// an existing shared LSP service to [CodeCrafter] without spawning duplicate
/// language server processes per editor tab.
class LspBridgeConfig extends LspConfig {
  final Future<void> Function()? onInitialize;
  final Future<void> Function()? onOpen;
  final Future<void> Function(String content)? onUpdate;
  final Future<void> Function()? onClose;
  final Future<List<LspCompletion>> Function(int line, int character)?
      onCompletion;
  final Future<String> Function(int line, int character)? onHover;

  LspBridgeConfig({
    required super.filePath,
    required super.workspacePath,
    required super.languageId,
    super.disableWarning = false,
    super.disableError = false,
    this.onInitialize,
    this.onOpen,
    this.onUpdate,
    this.onClose,
    this.onCompletion,
    this.onHover,
  });

  /// Pushes LSP-formatted diagnostics into [responses] so [CodeCrafter]
  /// highlights errors/warnings and shows hover diagnostic messages.
  void pushDiagnostics(List<Map<String, dynamic>> diagnostics) {
    if (!_responseController.isClosed) {
      _responseController.add({
        'method': 'textDocument/publishDiagnostics',
        'params': {'diagnostics': diagnostics},
      });
    }
  }

  @override
  Future<void> initialize() async {
    await onInitialize?.call();
  }

  @override
  Future<void> openDocument() async {
    await onOpen?.call();
  }

  @override
  Future<void> updateDocument(String content) async {
    await onUpdate?.call(content);
  }

  @override
  Future<void> closeDocument() async {
    await onClose?.call();
  }

  @override
  Future<List<LspCompletion>> getCompletions(int line, int character) async {
    if (onCompletion == null) return [];
    return onCompletion!(line, character);
  }

  @override
  Future<String> getHover(int line, int character) async {
    if (onHover == null) return '';
    return onHover!(line, character);
  }

  @override
  Future<Map<String, dynamic>> _sendRequest({
    required String method,
    required Map<String, dynamic> params,
  }) async =>
      const {};

  @override
  Future<void> _sendNotification({
    required String method,
    required Map<String, dynamic> params,
  }) async {}

  @override
  void dispose() {
    if (!_responseController.isClosed) {
      _responseController.close();
    }
  }
}
