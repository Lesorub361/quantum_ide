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
import 'package:quantum_ide/core/services/shizuku_bridge.dart';

import 'app.dart';

void main() async {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // Global error handlers
      FlutterError.onError = (FlutterErrorDetails details) {
        FlutterError.presentError(details);
        LogService.log(
          '[ERR] Flutter Error: ${details.exception}\n${details.stack}',
        );
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

      // Disable Android's Phantom Process Killer as early as possible.
      if (!kIsWeb && Platform.isAndroid) {
        unawaited(ShizukuBridge.instance.boostForBuild());
      }

      // Handle desktop-specific initialization
      if (!kIsWeb &&
          (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
        try {
          await _initializeDesktop();
        } catch (e) {
          debugPrint('Desktop initialization failed: $e');
        }
      }

      // Mount and launch UI immediately to ensure the user never gets a black/frozen screen
      runApp(const ProviderScope(child: QuantumApp()));

      // Defer secondary services until after first frame renders
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_initializeSecondaryServices());
      });

      // Request Android permissions asynchronously after UI first frame is mounted
      if (!kIsWeb && Platform.isAndroid) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _initializeAndroid();
        });
      }
    },
    (error, stack) {
      LogService.log('Uncaught Async Error: $error\n$stack');
      TalkerService.handle(error, stack, 'Uncaught Async Error');
    },
  );
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

/// Initialize non-critical services after the first frame is rendered
/// so app launch stays fast and responsive.
Future<void> _initializeSecondaryServices() async {
  try {
    QuickActionsService.instance.init();
  } catch (e) {
    LogService.log('[ERR] QuickActions init error: $e');
  }

  try {
    await KeyboardSoundService.init();
  } catch (e) {
    LogService.log('[ERR] KeyboardSoundService init error: $e');
  }

  try {
    NetworkInspectorService.init();
  } catch (e) {
    LogService.log('[ERR] NetworkInspectorService init error: $e');
  }

  try {
    await GhostQAService.instance.init();
  } catch (e) {
    LogService.log('[ERR] Ghost QA init error: $e');
  }

  try {
    await LiveTelemetryService.instance.init();
  } catch (e) {
    LogService.log('[ERR] LiveTelemetryService init error: $e');
  }
}
