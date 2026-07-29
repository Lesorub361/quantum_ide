import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/core/services/workspace_service.dart';

class MemoryData {
  final List<String> facts;
  final Map<String, dynamic> projectMeta;
  final List<Map<String, String>> skills;
  final String lastSummary;

  MemoryData({
    this.facts = const [],
    this.projectMeta = const {},
    this.skills = const [],
    this.lastSummary = '',
  });

  Map<String, dynamic> toJson() => {
        'facts': facts,
        'projectMeta': projectMeta,
        'skills': skills,
        'lastSummary': lastSummary,
      };

  factory MemoryData.fromJson(Map<String, dynamic> json) {
    return MemoryData(
      facts: List<String>.from(json['facts'] ?? []),
      projectMeta: Map<String, dynamic>.from(json['projectMeta'] ?? {}),
      skills: (json['skills'] as List?)
              ?.map((item) => Map<String, String>.from(item as Map))
              .toList() ??
          [],
      lastSummary: json['lastSummary'] as String? ?? '',
    );
  }
}

class AiMemoryService {
  final Ref _ref;
  MemoryData _cachedMemory = MemoryData();

  AiMemoryService(this._ref);

  MemoryData get cachedMemory => _cachedMemory;

  File _getMemoryFile(String workspacePath) {
    return File(p.join(workspacePath, '.quantum', 'ai_memory.json'));
  }

  Future<void> loadMemory() async {
    final workspace = _ref.read(workspaceProvider).currentPath;
    if (workspace == null) return;

    try {
      final file = _getMemoryFile(workspace);
      if (await file.exists()) {
        final content = await file.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        _cachedMemory = MemoryData.fromJson(json);
      } else {
        _cachedMemory = MemoryData();
      }
    } catch (e) {
      debugPrint('AiMemoryService: Failed to load memory: $e');
      _cachedMemory = MemoryData();
    }
  }

  Future<void> saveMemory() async {
    final workspace = _ref.read(workspaceProvider).currentPath;
    if (workspace == null) return;

    try {
      final file = _getMemoryFile(workspace);
      if (!await file.parent.exists()) {
        await file.parent.create(recursive: true);
      }
      final json = jsonEncode(_cachedMemory.toJson());
      await file.writeAsString(json);
    } catch (e) {
      debugPrint('AiMemoryService: Failed to save memory: $e');
    }
  }

  Future<void> addFact(String fact) async {
    if (!_cachedMemory.facts.contains(fact)) {
      _cachedMemory = MemoryData(
        facts: [..._cachedMemory.facts, fact],
        projectMeta: _cachedMemory.projectMeta,
        skills: _cachedMemory.skills,
        lastSummary: _cachedMemory.lastSummary,
      );
      await saveMemory();
    }
  }

  Future<void> removeFact(String fact) async {
    _cachedMemory = MemoryData(
      facts: _cachedMemory.facts.where((f) => f != fact).toList(),
      projectMeta: _cachedMemory.projectMeta,
      skills: _cachedMemory.skills,
      lastSummary: _cachedMemory.lastSummary,
    );
    await saveMemory();
  }

  Future<void> updateProjectMeta(String key, dynamic value) async {
    final meta = Map<String, dynamic>.from(_cachedMemory.projectMeta);
    meta[key] = value;
    _cachedMemory = MemoryData(
      facts: _cachedMemory.facts,
      projectMeta: meta,
      skills: _cachedMemory.skills,
      lastSummary: _cachedMemory.lastSummary,
    );
    await saveMemory();
  }

  Future<void> updateSummary(String summary) async {
    _cachedMemory = MemoryData(
      facts: _cachedMemory.facts,
      projectMeta: _cachedMemory.projectMeta,
      skills: _cachedMemory.skills,
      lastSummary: summary,
    );
    await saveMemory();
  }

  Future<void> addSkill(String name, String instruction) async {
    final skills = List<Map<String, String>>.from(_cachedMemory.skills);
    skills.removeWhere((s) => s['name'] == name);
    skills.add({'name': name, 'instruction': instruction});

    _cachedMemory = MemoryData(
      facts: _cachedMemory.facts,
      projectMeta: _cachedMemory.projectMeta,
      skills: skills,
      lastSummary: _cachedMemory.lastSummary,
    );
    await saveMemory();
  }

  Future<void> removeSkill(String name) async {
    final skills = _cachedMemory.skills.where((s) => s['name'] != name).toList();
    _cachedMemory = MemoryData(
      facts: _cachedMemory.facts,
      projectMeta: _cachedMemory.projectMeta,
      skills: skills,
      lastSummary: _cachedMemory.lastSummary,
    );
    await saveMemory();
  }
}

final aiMemoryServiceProvider = Provider((ref) {
  final service = AiMemoryService(ref);
  
  ref.listen<WorkspaceState>(workspaceProvider, (previous, next) {
    if (next.currentPath != null && next.currentPath != previous?.currentPath) {
      service.loadMemory();
    }
  });
  
  final current = ref.read(workspaceProvider).currentPath;
  if (current != null) {
    service.loadMemory();
  }
  
  return service;
});
