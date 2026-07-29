import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:quantum_ide/core/services/log_service.dart';
import 'app.dart';

void main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Initialize LogService with temporary directory
    final tempDir = await getTemporaryDirectory();
    await LogService.init(tempDir.path);

    // Intercept debugPrint
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) {
        LogService.log(message);
      }
    };

    // Global error handlers
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      LogService.log('Flutter Error: ${details.exception}\n${details.stack}');
    };

    // Handle platform-specific initialization
    try {
      if (Platform.isAndroid) {
        await _initializeAndroid();
      } else if (Platform.isLinux) {
        await _initializeLinux();
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
    // Примечание: разрешение камеры запрашивается только при реальном
    // использовании (вставка изображения в AI), не при старте.
    debugPrint('Android initialization complete');
  } catch (e) {
    debugPrint('Android initialization error: $e');
  }
}

/// Initialize Linux-specific settings
Future<void> _initializeLinux() async {
  try {
    // Set up Linux-specific environment if needed
    debugPrint('Linux initialization complete');
  } catch (e) {
    debugPrint('Linux initialization error: $e');
  }
}
