import 'dart:io';
import 'dart:ui' as ui;
import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:re_editor/re_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:quantum_ide/l10n/app_localizations.dart';
import 'package:quantum_ide/core/theme/app_theme.dart';
import 'package:quantum_ide/features/home/presentation/pages/home_page.dart';
import 'package:quantum_ide/features/editor/presentation/widgets/keyboard_accessory_bar.dart';

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

  testWidgets('Capture HomePage Phone and Tablet', (WidgetTester tester) async {
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      if (details.exceptionAsString().contains('GoogleFonts') || details.exceptionAsString().contains('font')) return;
      debugPrint('Layout error: ${details.exceptionAsString()}');
    };
    addTearDown(() => FlutterError.onError = originalOnError);

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
            child: const HomePage(),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(() async {
      await _captureRepaintKey(phoneKey, '/root/projects/quantum_ide/foto/03_phone_home.png');
    });

    // Tablet Home
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
            child: const HomePage(),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(() async {
      await _captureRepaintKey(tabletKey, '/root/projects/quantum_ide/foto/04_tablet_home.png');
    });
  });

  testWidgets('Capture KeyboardAccessoryBar Phone and Tablet', (WidgetTester tester) async {
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      if (details.exceptionAsString().contains('GoogleFonts') || details.exceptionAsString().contains('font')) return;
      debugPrint('Layout error: ${details.exceptionAsString()}');
    };
    addTearDown(() => FlutterError.onError = originalOnError);

    final controller = CodeLineEditingController.fromText('void main() {\n  print("Hello");\n}');
    final accPhoneKey = GlobalKey();
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
          home: Scaffold(
            backgroundColor: const Color(0xFF0F172A),
            body: Center(
              child: RepaintBoundary(
                key: accPhoneKey,
                child: Container(
                  width: 390,
                  color: const Color(0xFF0D0F14),
                  child: KeyboardAccessoryBar(controller: controller),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.runAsync(() async {
      await _captureRepaintKey(accPhoneKey, '/root/projects/quantum_ide/foto/05_phone_accessory_bar.png');
    });

    // Tablet accessory bar (1024 width)
    final accTabletKey = GlobalKey();
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
          home: Scaffold(
            backgroundColor: const Color(0xFF0F172A),
            body: Center(
              child: RepaintBoundary(
                key: accTabletKey,
                child: Container(
                  width: 1024,
                  color: const Color(0xFF0D0F14),
                  child: KeyboardAccessoryBar(controller: controller),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.runAsync(() async {
      await _captureRepaintKey(accTabletKey, '/root/projects/quantum_ide/foto/06_tablet_accessory_bar.png');
    });
  });
}
