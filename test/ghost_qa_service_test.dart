import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quantum_ide/core/services/ghost_qa_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GhostQAService Tests', () {
    test('Owner authorization test', () {
      final service = GhostQAService.instance;
      // In this dev container, owner_qa.key was created, so isAuthorized is true
      expect(service.isAuthorized, isTrue);
    });

    test('Error recording and retrieval', () {
      final service = GhostQAService.instance;
      service.clearErrors();
      expect(service.getErrors(), isEmpty);

      // Record standard error
      service.recordFlutterError(FlutterErrorDetails(
        exception: Exception('Test UI Exception'),
        library: 'widget library',
      ));

      // Record overflow error
      service.recordFlutterError(FlutterErrorDetails(
        exception: FlutterError('A RenderFlex overflowed by 42 pixels on the bottom.'),
        library: 'rendering library',
      ));

      final errors = service.getErrors();
      expect(errors.length, equals(2));
      expect(errors[0]['message'], contains('Test UI Exception'));
      expect(errors[0]['isOverflow'], isFalse);
      expect(errors[1]['message'], contains('RenderFlex overflowed'));
      expect(errors[1]['isOverflow'], isTrue);

      service.clearErrors();
      expect(service.getErrors(), isEmpty);
    });

    test('HTTP loopback server life cycle and endpoints', () async {
      HttpOverrides.global = null;
      final service = GhostQAService.instance;
      await service.init();

      final port = service.activePort;

      // Query health endpoint
      final client = HttpClient();
      final healthReq = await client.getUrl(Uri.parse('http://127.0.0.1:$port/health'));
      final healthResp = await healthReq.close();
      expect(healthResp.statusCode, equals(HttpStatus.ok));

      final healthBody = await utf8.decodeStream(healthResp);
      final healthJson = jsonDecode(healthBody) as Map<String, dynamic>;
      expect(healthJson['status'], equals('ok'));
      expect(healthJson['app'], equals('Quantum IDE'));
      expect(healthJson['authorized'], isTrue);

      // Record error and query /errors
      service.recordFlutterError(FlutterErrorDetails(
        exception: Exception('HTTP Error Test'),
      ));

      final errorsReq = await client.getUrl(Uri.parse('http://127.0.0.1:$port/errors'));
      final errorsResp = await errorsReq.close();
      expect(errorsResp.statusCode, equals(HttpStatus.ok));
      final errorsBody = await utf8.decodeStream(errorsResp);
      final errorsJson = jsonDecode(errorsBody) as Map<String, dynamic>;
      expect(errorsJson['count'], greaterThanOrEqualTo(1));

      // Clear via HTTP POST /clear_errors
      final clearReq = await client.postUrl(Uri.parse('http://127.0.0.1:$port/clear_errors'));
      final clearResp = await clearReq.close();
      expect(clearResp.statusCode, equals(HttpStatus.ok));
      expect(service.getErrors(), isEmpty);

      client.close();
      await service.dispose();
    });
  });
}
