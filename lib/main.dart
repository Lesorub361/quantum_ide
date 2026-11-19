import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:quantum_ide/core/services/sqlite/sqlite_facade.dart';
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
      LogService.log('[ERR] Flutter Error: ${details.exception}\n${details.stack}');
      GhostQAService.instance.recordFlutterError(details);
      TalkerService.handle(details.exception, details.stack, 'Flutter Error');
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      LogService.log('[ERR] Platform Error: $error\n$stack');
      TalkerService.handle(error, stack, 'Platform Error');
      return true;
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
      LogService.log('[OK] QuickActionsService initialized');
    } catch (e) {
      LogService.log('[ERR] QuickActions init error: $e');
    }

    // Initialize ASMR Mechanical Keyboard & Haptic Engine
    try {
      await KeyboardSoundService.init();
      LogService.log('[OK] KeyboardSoundService initialized');
    } catch (e) {
      LogService.log('[ERR] KeyboardSoundService init error: $e');
    }

    // Initialize In-App Network Inspector (Chucker)
    try {
      NetworkInspectorService.init();
      LogService.log('[OK] NetworkInspectorService initialized');
    } catch (e) {
      LogService.log('[ERR] NetworkInspectorService init error: $e');
    }

    // Initialize Ghost QA engine (only activates if owner is authorized)
    try {
      await GhostQAService.instance.init();
      LogService.log('[OK] GhostQAService initialized');
    } catch (e) {
      LogService.log('[ERR] Ghost QA init error: $e');
    }

    // Initialize Live Telemetry Bridge (metrics, logs and terminal monitoring)
    try {
      await LiveTelemetryService.instance.init();
      LogService.log('[OK] LiveTelemetryService initialized');
    } catch (e) {
      LogService.log('[ERR] LiveTelemetryService init error: $e');
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
    if (!kIsWeb && Platform.isAndroid) {
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
    initDesktopSqlite();
    debugPrint('Desktop initialization complete (SQLite FFI enabled)');
  } catch (e) {
    debugPrint('Desktop initialization error: $e');
  }
}
