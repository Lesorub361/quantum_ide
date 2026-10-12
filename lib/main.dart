import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:quantum_ide/core/services/log_service.dart';
import 'package:quantum_ide/core/services/ghost_qa_service.dart';
import 'app.dart';

void main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Initialize LogService with temporary directory
    final tempDir = await getTemporaryDirectory();
    await LogService.init(tempDir.path);

    // Global error handlers
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      LogService.log('Flutter Error: ${details.exception}\n${details.stack}');
      GhostQAService.instance.recordFlutterError(details);
    };

    // Initialize Ghost QA engine (only activates if owner is authorized)
    try {
      await GhostQAService.instance.init();
    } catch (e) {
      debugPrint('Ghost QA init error: $e');
    }

    // Handle platform-specific initialization
    try {
      if (Platform.isAndroid) {
        await _initializeAndroid();
      } else if (!kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
        await _initializeDesktop();
      }
    } catch (e) {
      debugPrint('Platform initialization failed: $e');
    }

    runApp(
      const ProviderScope(
        child: QuantumApp(),
      ),
    );
  }, (error, stack) {
    LogService.log('Uncaught Async Error: $error\n$stack');
  });
}

/// Initialize Android-specific settings
Future<void> _initializeAndroid() async {
  try {
    // Request storage permissions for Android 11+
    if (await Permission.manageExternalStorage.isDenied) {
      final status = await Permission.manageExternalStorage.request();
      if (status.isDenied) {
        debugPrint('Storage permission denied by user');
      }
    }
    // Request notification permission for Android 13+ (POST_NOTIFICATIONS)
    // so background terminal and foreground session notifications are visible to the user
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }
    // Примечание: разрешение камеры запрашивается только при реальном
    // использовании (вставка изображения в AI), не при старте.
    debugPrint('Android initialization complete');
  } catch (e) {
    debugPrint('Android initialization error: $e');
  }
}

/// Initialize Desktop-specific settings (Linux, Windows, macOS)
Future<void> _initializeDesktop() async {
  try {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    debugPrint('Desktop initialization complete (SQLite FFI enabled)');
  } catch (e) {
    debugPrint('Desktop initialization error: $e');
  }
}
