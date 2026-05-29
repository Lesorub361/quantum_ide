import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:quantum_ide/models/project_model.dart';
import 'package:quantum_ide/core/services/project_service.dart';
import 'package:quantum_ide/core/services/runtime_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockRuntimeService extends RuntimeService {
  final String _mockDir;

  MockRuntimeService(this._mockDir);

  @override
  String get appDirectory => _mockDir;

  @override
  String get filesDir => _mockDir;

  @override
  Future<void> init() async {
    // No-op
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Native Android Project Initialization Tests', () {
    late Directory tempDir;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tempDir = await Directory.systemTemp.createTemp('quantum_android_test');
    });

    tearDown(() async {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    test('generate androidJava project structure', () async {
      final container = ProviderContainer(
        overrides: [
          runtimeServiceProvider.overrideWith((ref) => MockRuntimeService(tempDir.path)),
        ],
      );
      final service = container.read(projectServiceProvider.notifier);

      final projectPath = p.join(tempDir.path, 'my_java_app');
      await service.writeNativeAndroidFilesForTesting(
        projectPath,
        'my_java_app',
        ProjectType.androidJava,
        sdkVersion: 'com.example.javaapp',
      );

      // Verify root gradle files
      expect(await File(p.join(projectPath, 'settings.gradle.kts')).exists(), isTrue);
      expect(await File(p.join(projectPath, 'build.gradle.kts')).exists(), isTrue);

      // Verify app gradle and config
      expect(await File(p.join(projectPath, 'app', 'build.gradle.kts')).exists(), isTrue);
      expect(await File(p.join(projectPath, 'app', 'src', 'main', 'AndroidManifest.xml')).exists(), isTrue);

      // Verify Java source file
      final mainActivityFile = File(p.join(
        projectPath,
        'app',
        'src',
        'main',
        'java',
        'com',
        'example',
        'javaapp',
        'MainActivity.java',
      ));
      expect(await mainActivityFile.exists(), isTrue);

      final content = await mainActivityFile.readAsString();
      expect(content, contains('package com.example.javaapp;'));
      expect(content, contains('public class MainActivity extends AppCompatActivity'));
    });

    test('generate androidKotlin project structure with default package', () async {
      final container = ProviderContainer(
        overrides: [
          runtimeServiceProvider.overrideWith((ref) => MockRuntimeService(tempDir.path)),
        ],
      );
      final service = container.read(projectServiceProvider.notifier);

      final projectPath = p.join(tempDir.path, 'my_kt_app');
      await service.writeNativeAndroidFilesForTesting(
        projectPath,
        'my-kt-app',
        ProjectType.androidKotlin,
      );

      // Verify root gradle files
      expect(await File(p.join(projectPath, 'settings.gradle.kts')).exists(), isTrue);
      expect(await File(p.join(projectPath, 'build.gradle.kts')).exists(), isTrue);

      // Verify app gradle and config
      expect(await File(p.join(projectPath, 'app', 'build.gradle.kts')).exists(), isTrue);
      expect(await File(p.join(projectPath, 'app', 'src', 'main', 'AndroidManifest.xml')).exists(), isTrue);

      // Verify Kotlin source file in the default package directory
      final mainActivityFile = File(p.join(
        projectPath,
        'app',
        'src',
        'main',
        'java',
        'com',
        'example',
        'my_kt_app',
        'MainActivity.kt',
      ));
      expect(await mainActivityFile.exists(), isTrue);

      final content = await mainActivityFile.readAsString();
      expect(content, contains('package com.example.my_kt_app'));
      expect(content, contains('class MainActivity : AppCompatActivity()'));
    });
  });
}
