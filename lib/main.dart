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
import 'package:quantum_ide/core/services/talker_service.dart';
import 'package:quantum_ide/core/services/quick_actions_service.dart';
import 'package:quantum_ide/core/services/keyboard_sound_service.dart';
import 'package:quantum_ide/core/services/network_inspector_service.dart';
import 'package:quantum_ide/core/services/live_telemetry_service.dart';
import 'app.dart';

void main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Global error handlers
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      LogService.log('Flutter Error: ${details.exception}\n${details.stack}');
      GhostQAService.instance.recordFlutterError(details);
      TalkerService.handle(details.exception, details.stack, 'Flutter Error');
    };

    // Initialize LogService with temporary directory safely
    try {
      final tempDir = await getTemporaryDirectory();
      await LogService.init(tempDir.path);
    } catch (e) {
      debugPrint('LogService init error: $e');
    }

    // Initialize Quick Actions (App Shortcuts)
    try {
      QuickActionsService.instance.init();
    } catch (e) {
      debugPrint('QuickActions init error: $e');
    }

    // Initialize ASMR Mechanical Keyboard & Haptic Engine
    try {
      await KeyboardSoundService.init();
    } catch (e) {
      debugPrint('KeyboardSoundService init error: $e');
    }

    // Initialize In-App Network Inspector (Chucker)
    try {
      NetworkInspectorService.init();
    } catch (e) {
      debugPrint('NetworkInspectorService init error: $e');
    }

    // Initialize Ghost QA engine (only activates if owner is authorized)
    try {
      await GhostQAService.instance.init();
    } catch (e) {
      debugPrint('Ghost QA init error: $e');
    }

    // Initialize Live Telemetry Bridge (metrics, logs and terminal monitoring)
    try {
      await LiveTelemetryService.instance.init();
    } catch (e) {
      debugPrint('LiveTelemetryService init error: $e');
    }

    // Handle desktop-specific initialization
    if (!kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
      try {
        await _initializeDesktop();
      } catch (e) {
        debugPrint('Desktop initialization failed: $e');
      }
    }

    // Mount and launch UI immediately to ensure the user never gets a black/frozen screen
    runApp(
      const ProviderScope(
        child: QuantumApp(),
      ),
    );

    // Request Android permissions asynchronously after UI first frame is mounted
    if (Platform.isAndroid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _initializeAndroid();
      });
    }
  }, (error, stack) {
    LogService.log('Uncaught Async Error: $error\n$stack');
    TalkerService.handle(error, stack, 'Uncaught Async Error');
  });
}

/// Initialize Android-specific settings non-blockingly
Future<void> _initializeAndroid() async {
  try {
    // Request notification permission for Android 13+ (POST_NOTIFICATIONS)
    // so background terminal and foreground session notifications are visible to the user
    try {
      if (await Permission.notification.isDenied) {
        await Permission.notification.request();
      }
    } catch (e) {
      debugPrint('Notification permission error: $e');
    }

    // Request storage permissions for Android 11+
    try {
      if (await Permission.manageExternalStorage.isDenied) {
        await Permission.manageExternalStorage.request().timeout(
          const Duration(seconds: 15),
          onTimeout: () => PermissionStatus.denied,
        );
      }
    } catch (e) {
      debugPrint('Storage permission error: $e');
    }

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
