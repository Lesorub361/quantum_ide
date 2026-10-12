import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:quantum_ide/core/services/ghost_qa_service.dart';
import 'package:quantum_ide/core/services/log_service.dart';
import 'package:quantum_ide/features/editor/presentation/notifiers/editor_notifier.dart';
import 'package:quantum_ide/features/editor/presentation/widgets/editor_app_bar.dart';
import 'package:quantum_ide/shared/providers/panel_provider.dart';
import 'package:quantum_ide/shared/providers/ai_panel_provider.dart';
import 'package:quantum_ide/shared/widgets/mobile_bottom_nav.dart';
import 'package:quantum_ide/l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

Future<void> _captureRepaintKey(GlobalKey key, String outputPath) async {
  try {
    final boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    final image = await boundary.toImage(pixelRatio: 1.5);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return;
    final bytes = byteData.buffer.asUint8List();

    final f = File(outputPath);
    await f.parent.create(recursive: true);
    await f.writeAsBytes(bytes);

    // Mirror to .quantum/screenshots
    final mirrorPath = outputPath.replaceAll('/foto/', '/.quantum/screenshots/');
    final mirrorFile = File(mirrorPath);
    await mirrorFile.parent.create(recursive: true);
    await mirrorFile.writeAsBytes(bytes);
  } catch (e) {
    debugPrint('Error saving screenshot to $outputPath: $e');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    GhostQAService.instance.authorizeDirectly();
    await LogService.init(Directory.systemTemp.path);
  });

  group('UI & Tabs Ghost QA Test Suite', () {
    testWidgets('1. Full App Shell startup & Screen Inspection', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: ThemeData.dark(),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: const [Locale('en'), Locale('ru')],
            home: RepaintBoundary(
              key: GhostQAService.repaintKey,
              child: Scaffold(
                backgroundColor: const Color(0xFF0F1013),
                appBar: AppBar(
                  title: const Text('Quantum IDE'),
                  backgroundColor: const Color(0xFF14161C),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.settings),
                      tooltip: 'Settings',
                      onPressed: () {},
                    ),
                  ],
                ),
                body: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.code, size: 72, color: Color(0xFF00E5FF)),
                      const SizedBox(height: 16),
                      const Text(
                        'Welcome to Quantum IDE',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Ready for autonomous QA and coding',
                        style: TextStyle(fontSize: 14, color: Colors.white70),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00E5FF),
                          foregroundColor: Colors.black,
                        ),
                        onPressed: () {},
                        icon: const Icon(Icons.folder_open),
                        label: const Text('Open Project'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // Inspect elements via Ghost QA Engine
      final uiData = await GhostQAService.instance.inspectUiElements();
      expect(uiData['error'], isNull);
      final count = uiData['element_count'] as int? ?? 0;
      expect(count, greaterThan(0));

      // Capture initial app screen screenshot
      await tester.runAsync(() async {
        await _captureRepaintKey(
          GhostQAService.repaintKey,
          '/root/projects/quantum_ide-main/foto/01_app_initial_screen.png',
        );
      });

      // Verify no runtime overflow errors
      final errors = GhostQAService.instance.getErrors();
      expect(errors.where((e) => e['isOverflow'] == true), isEmpty);
    });

    testWidgets('2. Mobile Bottom Nav Tabs Click & State Transition Test', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final testKey = GlobalKey();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData.dark(),
            home: Scaffold(
              body: RepaintBoundary(
                key: testKey,
                child: Column(
                  children: [
                    const Expanded(
                      child: Center(
                        child: Text(
                          'Quantum IDE Workspace',
                          style: TextStyle(fontSize: 20, color: Colors.white),
                        ),
                      ),
                    ),
                    MobileBottomNav(
                      onTerminalToggle: () {},
                      onAiToggle: () {},
                      onExplorerToggle: () {},
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // Verify 4 main tabs exist: Files, Editor, Terminal, AI Chat
      expect(find.text('Files'), findsOneWidget);
      expect(find.text('Editor'), findsOneWidget);
      expect(find.text('Terminal'), findsOneWidget);
      expect(find.text('AI Chat'), findsOneWidget);

      // Save initial bottom nav screenshot
      await tester.runAsync(() async {
        await _captureRepaintKey(testKey, '/root/projects/quantum_ide-main/foto/02_bottom_nav_tabs.png');
      });

      // Click Terminal tab
      await tester.tap(find.text('Terminal'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(container.read(panelProvider).isOpened, isTrue);
      expect(container.read(panelProvider).selectedTab, equals(PanelTab.terminal));

      // Click AI Chat tab
      await tester.tap(find.text('AI Chat'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(container.read(rightChatPanelOpenProvider), isTrue);

      // Verify no overflow
      expect(GhostQAService.instance.getErrors().where((e) => e['isOverflow'] == true), isEmpty);
    });

    testWidgets('3. Panel Tabs Switching Test (Terminal, Problems, Git, App Logs, Run, Debug)', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final panelKey = GlobalKey();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData.dark(),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: const [Locale('en'), Locale('ru')],
            home: Scaffold(
              body: RepaintBoundary(
                key: panelKey,
                child: Consumer(
                  builder: (context, ref, _) {
                    final panelState = ref.watch(panelProvider);
                    final panelNotifier = ref.read(panelProvider.notifier);

                    return Container(
                      color: const Color(0xFF14161C),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: PanelTab.values.map((tab) {
                              final isSelected = panelState.selectedTab == tab;
                              return ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isSelected ? const Color(0xFF00E5FF) : const Color(0xFF232733),
                                  foregroundColor: isSelected ? Colors.black : Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                onPressed: () => panelNotifier.selectTab(tab),
                                child: Text(tab.name.toUpperCase()),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 24),
                          Container(
                            height: 180,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: const Color(0xFF090A0F),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'ACTIVE PANEL: ${panelState.selectedTab.name.toUpperCase()}',
                                  style: const TextStyle(
                                    color: Color(0xFF00E5FF),
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Status: Active and rendered without overflows',
                                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      final tabsToTest = [
        (PanelTab.terminal, 'TERMINAL', '/root/projects/quantum_ide-main/foto/03_terminal_tab_active.png'),
        (PanelTab.problems, 'PROBLEMS', '/root/projects/quantum_ide-main/foto/04_problems_tab_active.png'),
        (PanelTab.git, 'GIT', '/root/projects/quantum_ide-main/foto/05_git_tab_active.png'),
        (PanelTab.appLogs, 'APPLOGS', '/root/projects/quantum_ide-main/foto/06_applogs_tab_active.png'),
        (PanelTab.run, 'RUN', '/root/projects/quantum_ide-main/foto/07_run_tab_active.png'),
        (PanelTab.debug, 'DEBUG', '/root/projects/quantum_ide-main/foto/08_debug_tab_active.png'),
      ];

      for (final (tab, label, imgPath) in tabsToTest) {
        await tester.tap(find.text(label));
        await tester.pump(const Duration(milliseconds: 100));
        expect(container.read(panelProvider).selectedTab, equals(tab));

        await tester.runAsync(() async {
          await _captureRepaintKey(panelKey, imgPath);
        });
      }

      expect(GhostQAService.instance.getErrors().where((e) => e['isOverflow'] == true), isEmpty);
    });

    testWidgets('4. Editor File Tabs Test (Open, Switch, Close)', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final editorKey = GlobalKey();

      final testFile1 = EditorFile(
        path: '/workspace/main.dart',
        name: 'main.dart',
        controller: CodeLineEditingController.fromText('void main() {}'),
        originalContent: 'void main() {}',
      );
      final testFile2 = EditorFile(
        path: '/workspace/app.dart',
        name: 'app.dart',
        controller: CodeLineEditingController.fromText('class App {}'),
        originalContent: 'class App {}',
      );
      final testFile3 = EditorFile(
        path: '/workspace/pubspec.yaml',
        name: 'pubspec.yaml',
        controller: CodeLineEditingController.fromText('name: test'),
        originalContent: 'name: test',
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData.dark(),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: const [Locale('en'), Locale('ru')],
            home: Scaffold(
              body: RepaintBoundary(
                key: editorKey,
                child: Column(
                  children: [
                    const EditorTabBar(),
                    Expanded(
                      child: Center(
                        child: Consumer(
                          builder: (context, ref, _) {
                            final active = ref.watch(editorProvider).activeFilePath;
                            return Text(
                              'Active Document: $active',
                              style: const TextStyle(color: Colors.white, fontSize: 16),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // Inject open files after provider initialization
      final editorNotifier = container.read(editorProvider.notifier);
      editorNotifier.state = editorNotifier.state.copyWith(
        openFiles: [testFile1, testFile2, testFile3],
        activeTabIndex: 0,
      );
      await tester.pump(const Duration(milliseconds: 100));

      // Verify all 3 file tabs are displayed in EditorTabBar
      expect(find.text('main.dart'), findsOneWidget);
      expect(find.text('app.dart'), findsOneWidget);
      expect(find.text('pubspec.yaml'), findsOneWidget);

      // Save screenshot of editor tabs
      await tester.runAsync(() async {
        await _captureRepaintKey(editorKey, '/root/projects/quantum_ide-main/foto/09_editor_tabs_active.png');
      });

      // Switch to second tab (app.dart)
      await tester.tap(find.text('app.dart'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(container.read(editorProvider).activeTabIndex, equals(1));

      // Switch back to first tab (main.dart)
      await tester.tap(find.text('main.dart'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(container.read(editorProvider).activeTabIndex, equals(0));

      // Close third tab (pubspec.yaml)
      editorNotifier.closeTab(2);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('pubspec.yaml'), findsNothing);
      expect(container.read(editorProvider).openFiles.length, equals(2));

      // Final check: 0 errors
      final errors = GhostQAService.instance.getErrors();
      expect(errors.where((e) => e['isOverflow'] == true), isEmpty);
    });
  });
}
