import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
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

    // Intercept debugPrint (only in debug mode to avoid disk/stdout overhead
    // in release builds, where the framework emits far too many messages)
    if (kDebugMode) {
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) {
          LogService.log(message);
        }
      };
    }

    // Named to re-throw when running tests, so test failures are still visible.
    FlutterError.onError = kReleaseMode
        ? _logFlutterError
        : (details) {
            FlutterError.presentError(details);
            _logFlutterError(details);
          };

    // Global engine-level error handler. Returning true tells the engine that
    // the error was handled so the app never silently exits/crashes. All
    // errors are persisted so they can be diagnosed later.
    PlatformDispatcher.instance.onError = (error, stack) {
      LogService.log('Engine Error: $error\n$stack');
      return true;
    };

    // Prevent any single broken widget from crashing the whole app by showing
    // a friendly fallback instead of the default crashing render path.
    ErrorWidget.builder = (FlutterErrorDetails details) {
      LogService.log('Widget Build Error: ${details.exception}\n${details.stack}');
      return const _FallbackErrorWidget();
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

/// Logs a Flutter framework error without attempting to terminate the app.
void _logFlutterError(FlutterErrorDetails details) {
  LogService.log('Flutter Error: ${details.exception}\n${details.stack}');
  // notifyListeners is the only framework fallback; keep it so the error
  // still reaches the debug console in tooling.
  if (!kReleaseMode) {
    FlutterError.dumpErrorToConsole(details, forceReport: false);
  }
}

/// Minimal fallback shown in place of any widget whose build failed, so a
/// single bad widget can't close the application.
class _FallbackErrorWidget extends StatelessWidget {
  const _FallbackErrorWidget();

  @override
  Widget build(BuildContext context) {
    return const Material(
      color: Color(0xFF1E1E2E),
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: Color(0xFFF38BA8), size: 28),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Something went wrong rendering this panel. Error logged to .quantum/app.log',
                style: TextStyle(color: Color(0xFFCDD6F4), fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
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
