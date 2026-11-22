import 'package:conduit_vt/conduit_vt.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quantum_ide/core/services/live_telemetry_service.dart';
import 'package:quantum_ide/shared/widgets/keyboard_visibility_builder.dart';

void main() {
  group('Keyboard visibility optimizations', () {
    testWidgets(
      'KeyboardVisibilty fires onKeyboardShow once on open and onKeyboardHide once on close',
      (tester) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.viewInsets = FakeViewPadding.zero;
        addTearDown(() {
          tester.view.resetViewInsets();
          tester.view.resetDevicePixelRatio();
        });

        int showCount = 0;
        int hideCount = 0;

        await tester.pumpWidget(
          MaterialApp(
            home: KeyboardVisibilty(
              onKeyboardShow: () => showCount++,
              onKeyboardHide: () => hideCount++,
              child: const SizedBox.expand(),
            ),
          ),
        );

        expect(showCount, 0);
        expect(hideCount, 0);

        for (final bottom in [100.0, 250.0, 500.0]) {
          tester.view.viewInsets = FakeViewPadding(bottom: bottom);
          await tester.pump();
        }
        expect(showCount, 1);
        expect(hideCount, 0);

        for (final bottom in [300.0, 120.0, 0.0]) {
          tester.view.viewInsets = FakeViewPadding(bottom: bottom);
          await tester.pump();
        }
        expect(showCount, 1);
        expect(hideCount, 1);
      },
    );

    testWidgets(
      'KeyboardVisibilityBuilder rebuilds only when crossing threshold',
      (tester) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.viewInsets = FakeViewPadding.zero;
        addTearDown(() {
          tester.view.resetViewInsets();
          tester.view.resetDevicePixelRatio();
        });

        int buildCount = 0;
        bool? latestOpen;

        await tester.pumpWidget(
          MaterialApp(
            home: KeyboardVisibilityBuilder(
              threshold: 20.0,
              builder: (context, isOpen) {
                buildCount++;
                latestOpen = isOpen;
                return SizedBox.expand(key: ValueKey(isOpen));
              },
            ),
          ),
        );

        expect(buildCount, 1);
        expect(latestOpen, isFalse);

        // Below threshold: should not rebuild.
        tester.view.viewInsets = const FakeViewPadding(bottom: 10);
        await tester.pump();
        expect(buildCount, 1);
        expect(latestOpen, isFalse);

        // Crosses threshold (> 20): single rebuild.
        tester.view.viewInsets = const FakeViewPadding(bottom: 40);
        await tester.pump();
        expect(buildCount, 2);
        expect(latestOpen, isTrue);

        // Further animation frames stay open without rebuilding.
        for (final bottom in [120.0, 240.0, 320.0]) {
          tester.view.viewInsets = FakeViewPadding(bottom: bottom);
          await tester.pump();
        }
        expect(buildCount, 2);
        expect(latestOpen, isTrue);

        // Closing back below threshold triggers one rebuild.
        tester.view.viewInsets = FakeViewPadding.zero;
        await tester.pump();
        expect(buildCount, 3);
        expect(latestOpen, isFalse);
      },
    );
  });

  group('RenderTerminal resize debouncing', () {
    testWidgets(
      'performs initial resize immediately, debounces rapid resizes, and respects autoResize: false',
      (tester) async {
        int resizeCount = 0;
        final terminal = Terminal(
          maxLines: 500,
          onResize: (w, h, pw, ph) {
            resizeCount++;
          },
        );
        final heightNotifier = ValueNotifier<double>(400);
        final autoResizeNotifier = ValueNotifier<bool>(true);
        addTearDown(() {
          heightNotifier.dispose();
          autoResizeNotifier.dispose();
        });

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ValueListenableBuilder<double>(
                valueListenable: heightNotifier,
                builder: (context, height, _) {
                  return ValueListenableBuilder<bool>(
                    valueListenable: autoResizeNotifier,
                    builder: (context, autoResize, _) {
                      return Center(
                        child: SizedBox(
                          width: 400,
                          height: height,
                          child: TerminalView(
                            terminal,
                            autoResize: autoResize,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        );

        expect(resizeCount, 1);

        // Rapid height changes (e.g. keyboard animation) coalesce within 140ms.
        for (final h in [340.0, 280.0, 220.0]) {
          heightNotifier.value = h;
          await tester.pump(const Duration(milliseconds: 30));
        }
        expect(resizeCount, 1);

        await tester.pump(const Duration(milliseconds: 160));
        expect(resizeCount, 2);

        // When autoResize is false (hidden tab), height changes must not trigger resize.
        autoResizeNotifier.value = false;
        await tester.pump();
        heightNotifier.value = 140.0;
        await tester.pump(const Duration(milliseconds: 200));
        expect(resizeCount, 2);
      },
    );
  });

  group('LiveTelemetryService', () {
    test('tracks Built build/web completion, exposes shizuku status, and returns newest logs', () {
      final telemetry = LiveTelemetryService.instance;
      for (var i = 0; i < 25; i++) {
        telemetry.logEvent('test_event_$i');
      }

      telemetry.onBuildStarted('flutter build web');
      expect(telemetry.isBuilding, isTrue);

      telemetry.appendBuildOutput('✓ Built build/web');
      expect(telemetry.isBuilding, isFalse);
      expect(telemetry.currentBuildStatus, startsWith('Success'));

      final snapshot = telemetry.statusSnapshot;
      expect(snapshot['shizuku'], isA<Map<String, dynamic>>());
      final shizuku = snapshot['shizuku'] as Map<String, dynamic>;
      expect(
        shizuku.keys,
        containsAll(<String>[
          'available',
          'binderAlive',
          'permissionGranted',
          'uid',
          'error',
        ]),
      );

      final tail = snapshot['recentLogsTail'] as List<dynamic>;
      expect(tail.length, 20);
      expect(tail.last.toString(), contains('test_event_24'));
    });
  });
}
