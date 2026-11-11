import 'dart:io';
import 'dart:ui' as ui;
import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:quantum_ide/l10n/app_localizations.dart';
import 'package:quantum_ide/core/theme/app_theme.dart';
import 'package:quantum_ide/features/home/presentation/pages/package_page.dart';

Future<void> _captureRepaintKey(GlobalKey key, String outputPath) async {
  try {
    final boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) {
      debugPrint('Warning: Boundary is null for $outputPath');
      return;
    }
    final image = await boundary.toImage(pixelRatio: 1.5);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return;
    final bytes = byteData.buffer.asUint8List();
    final f = File(outputPath);
    await f.parent.create(recursive: true);
    await f.writeAsBytes(bytes);
    debugPrint('Saved screenshot: $outputPath (${bytes.length} bytes)');
  } catch (e, st) {
    debugPrint('Error saving screenshot: $e\n$st');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Capture PackagePage Phone and Tablet screenshots', (WidgetTester tester) async {
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      debugPrint('Captured layout error: ${details.exceptionAsString()}');
    };
    addTearDown(() => FlutterError.onError = originalOnError);

    // 1. Phone Viewport (390 x 844)
    final phoneKey = GlobalKey();
    tester.view.physicalSize = const Size(390 * 2, 844 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.dark(FlexScheme.deepBlue),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('ru'),
          home: RepaintBoundary(
            key: phoneKey,
            child: const Scaffold(
              body: PackagePage(),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.runAsync(() async {
      await _captureRepaintKey(phoneKey, '/root/projects/quantum_ide/foto/01_phone_packages_current.png');
    });

    // 2. Tablet Viewport (1024 x 768)
    final tabletKey = GlobalKey();
    tester.view.physicalSize = const Size(1024 * 2, 768 * 2);
    tester.view.devicePixelRatio = 2.0;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.dark(FlexScheme.deepBlue),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('ru'),
          home: RepaintBoundary(
            key: tabletKey,
            child: const Scaffold(
              body: PackagePage(),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.runAsync(() async {
      await _captureRepaintKey(tabletKey, '/root/projects/quantum_ide/foto/02_tablet_packages_current.png');
    });
  });
}
