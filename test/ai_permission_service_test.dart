import 'package:flutter_test/flutter_test.dart';
import 'package:quantum_ide/core/services/ai_permission_service.dart';
import 'package:quantum_ide/models/chat_message.dart';

void main() {
  group('AiPermissionService Tests', () {
    const service = AiPermissionService();
    const workspaceRoot = '/home/user/project';

    group('Path Scoping', () {
      test('Path inside workspace is in scope', () {
        expect(
          service.isPathInScope('/home/user/project/lib/main.dart', workspaceRoot),
          isTrue,
        );
        expect(
          service.isPathInScope('/home/user/project/pubspec.yaml', workspaceRoot),
          isTrue,
        );
      });

      test('Path outside workspace is out of scope', () {
        expect(
          service.isPathInScope('/home/user/other_project/lib/main.dart', workspaceRoot),
          isFalse,
        );
        expect(
          service.isPathInScope('/etc/passwd', workspaceRoot),
          isFalse,
        );
      });

      test('Relative path traverses outside workspace is out of scope', () {
        expect(
          service.isPathInScope('/home/user/project/../other/main.dart', workspaceRoot),
          isFalse,
        );
      });
    });

    group('Risk Scoring', () {
      test('Edits and creations in workspace are MEDIUM', () {
        final action = AIAction(
          type: 'edit',
          path: '/home/user/project/lib/main.dart',
          content: 'void main() {}',
        );
        expect(
          service.evaluateActionRisk(action, workspaceRoot),
          equals(AiRiskLevel.medium),
        );
      });

      test('Deletions in workspace are HIGH', () {
        final deleteAction = AIAction(
          type: 'delete',
          path: '/home/user/project/lib/main.dart',
          content: '',
        );
        expect(
          service.evaluateActionRisk(deleteAction, workspaceRoot),
          equals(AiRiskLevel.high),
        );
      });

      test('Commands like flutter test or git status are LOW', () {
        final cmdAction = AIAction(
          type: 'command',
          path: '',
          content: 'flutter test',
        );
        expect(
          service.evaluateActionRisk(cmdAction, workspaceRoot),
          equals(AiRiskLevel.low),
        );
      });

      test('Commands like git commit or pub get (not in low risk list) are MEDIUM', () {
        final cmdAction = AIAction(
          type: 'command',
          path: '',
          content: 'flutter pub get',
        );
        expect(
          service.evaluateActionRisk(cmdAction, workspaceRoot),
          equals(AiRiskLevel.medium),
        );
      });

      test('Potentially dangerous commands are HIGH', () {
        final rmAction = AIAction(
          type: 'command',
          path: '',
          content: 'rm -rf /home/user/project',
        );
        expect(
          service.evaluateActionRisk(rmAction, workspaceRoot),
          equals(AiRiskLevel.high),
        );
      });

      test('Actions referencing out-of-scope paths are HIGH', () {
        final editAction = AIAction(
          type: 'edit',
          path: '/etc/passwd',
          content: 'root:x:0:0:root:/root:/bin/bash',
        );
        expect(
          service.evaluateActionRisk(editAction, workspaceRoot),
          equals(AiRiskLevel.high),
        );
      });
    });

    group('Path Candidates Extraction', () {
      test('Extract paths from command text', () {
        final paths = service.extractPathCandidates('cat /etc/passwd /home/user/file.txt');
        expect(paths, contains('/etc/passwd'));
        expect(paths, contains('/home/user/file.txt'));
      });
    });
  });
}
