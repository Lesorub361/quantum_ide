import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quantum_ide/core/services/collaboration_service.dart';

class VectorClock {
  final Map<String, int> _clocks;

  VectorClock([Map<String, int>? clocks]) : _clocks = clocks != null ? Map.from(clocks) : {};

  int operator [](String peerId) => _clocks[peerId] ?? 0;

  void increment(String peerId) {
    _clocks[peerId] = (_clocks[peerId] ?? 0) + 1;
  }

  void merge(VectorClock other) {
    for (final entry in other._clocks.entries) {
      final current = _clocks[entry.key] ?? 0;
      if (entry.value > current) {
        _clocks[entry.key] = entry.value;
      }
    }
  }

  bool concurrentlyWith(VectorClock other) {
    bool thisGreater = false;
    bool otherGreater = false;
    final allKeys = {..._clocks.keys, ...other._clocks.keys};
    for (final key in allKeys) {
      final a = _clocks[key] ?? 0;
      final b = other._clocks[key] ?? 0;
      if (a > b) thisGreater = true;
      if (b > a) otherGreater = true;
    }
    return thisGreater && otherGreater;
  }

  Map<String, int> toJson() => Map<String, int>.from(_clocks);
  factory VectorClock.fromJson(Map<String, dynamic> json) {
    final intMap = <String, int>{};
    json.forEach((k, v) {
      if (v is int) intMap[k] = v;
    });
    return VectorClock(intMap);
  }

  @override
  String toString() => 'VC(${_clocks.entries.map((e) => '${e.key}:${e.value}').join(', ')})';
}

class CrdtOperation {
  final String id;
  final String peerId;
  final String type;
  final int position;
  final String? content;
  final int? length;
  final VectorClock clock;

  CrdtOperation({
    required this.id,
    required this.peerId,
    required this.type,
    required this.position,
    this.content,
    this.length,
    required this.clock,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'peerId': peerId,
    'type': type,
    'position': position,
    'content': content,
    'length': length,
    'clock': clock.toJson(),
  };

  factory CrdtOperation.fromJson(Map<String, dynamic> json) => CrdtOperation(
    id: json['id'],
    peerId: json['peerId'],
    type: json['type'],
    position: json['position'],
    content: json['content'],
    length: json['length'],
    clock: VectorClock.fromJson(json['clock']),
  );
}

class CrdtDocument {
  String text;
  final VectorClock clock;
  final List<CrdtOperation> history;

  CrdtDocument({
    this.text = '',
    VectorClock? clock,
    List<CrdtOperation>? history,
  })  : clock = clock ?? VectorClock(),
        history = history ?? [];
}

class CrdtSyncService extends ChangeNotifier {
  final CollaborationService _collaboration;
  final Map<String, CrdtDocument> _documents = {};
  String? _localPeerId;

  CrdtSyncService(this._collaboration);

  String get localPeerId => _localPeerId ?? 'local';
  Map<String, CrdtDocument> get documents => Map.unmodifiable(_documents);

  void setLocalPeerId(String id) {
    _localPeerId = id;
  }

  void initializeDocument(String path, {String initialContent = ''}) {
    if (_documents.containsKey(path)) return;
    _documents[path] = CrdtDocument(text: initialContent);
    notifyListeners();
  }

  String getDocumentContent(String path) {
    return _documents[path]?.text ?? '';
  }

  CrdtOperation insert(String path, int position, String content) {
    final doc = _documents[path];
    if (doc == null) return throw StateError('Document not initialized: $path');

    doc.clock.increment(localPeerId);
    final op = CrdtOperation(
      id: '${localPeerId}_${DateTime.now().microsecondsSinceEpoch}',
      peerId: localPeerId,
      type: 'insert',
      position: position,
      content: content,
      clock: VectorClock(doc.clock.toJson()),
    );

    _applyOperation(doc, op);
    _broadcastOperation(path, op);
    notifyListeners();
    return op;
  }

  CrdtOperation delete(String path, int position, int length) {
    final doc = _documents[path];
    if (doc == null) return throw StateError('Document not initialized: $path');

    doc.clock.increment(localPeerId);
    final op = CrdtOperation(
      id: '${localPeerId}_${DateTime.now().microsecondsSinceEpoch}',
      peerId: localPeerId,
      type: 'delete',
      position: position,
      length: length,
      clock: VectorClock(doc.clock.toJson()),
    );

    _applyOperation(doc, op);
    _broadcastOperation(path, op);
    notifyListeners();
    return op;
  }

  void _applyOperation(CrdtDocument doc, CrdtOperation op) {
    switch (op.type) {
      case 'insert':
        final pos = op.position.clamp(0, doc.text.length);
        doc.text = '${doc.text.substring(0, pos)}${op.content ?? ''}${doc.text.substring(pos)}';
        break;
      case 'delete':
        final pos = op.position.clamp(0, doc.text.length);
        final len = (op.length ?? 0).clamp(0, doc.text.length - pos);
        doc.text = '${doc.text.substring(0, pos)}${doc.text.substring(pos + len)}';
        break;
    }
    doc.clock.merge(op.clock);
    doc.history.add(op);
  }

  void _broadcastOperation(String path, CrdtOperation op) {
    try {
      _collaboration.sendChatMessage(jsonEncode({
        'type': 'crdt_op',
        'filePath': path,
        'operation': op.toJson(),
      }));
    } catch (e) {
      debugPrint('CrdtSyncService: broadcast failed: $e');
    }
  }

  void handleRemoteOperation(String path, CrdtOperation op) {
    if (!_documents.containsKey(path)) {
      initializeDocument(path);
    }
    final doc = _documents[path]!;

    if (doc.clock.concurrentlyWith(op.clock)) {
      debugPrint('CrdtSyncService: concurrent edit detected from ${op.peerId}');
    }

    _applyOperation(doc, op);
    notifyListeners();
  }

  @override
  void dispose() {
    _documents.clear();
    super.dispose();
  }
}

final crdtSyncServiceProvider = ChangeNotifierProvider<CrdtSyncService>((ref) {
  final collab = ref.watch(collaborationProvider.notifier);
  final service = CrdtSyncService(collab);
  ref.onDispose(() => service.dispose());
  return service;
});
