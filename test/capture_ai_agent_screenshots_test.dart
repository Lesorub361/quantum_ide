import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:quantum_ide/core/services/quantum_ai_agent_service.dart';
import 'package:quantum_ide/core/services/runtime_service.dart';
import 'package:quantum_ide/core/services/settings_service.dart';
import 'package:quantum_ide/core/services/workspace_service.dart';
import 'package:quantum_ide/features/editor/presentation/widgets/quantum_ai_agent_panel.dart';
import 'package:quantum_ide/l10n/app_localizations.dart';

late final List<int> _fontBytes;

class _MockHttpClient extends Fake implements HttpClient {
  @override
  Duration idleTimeout = const Duration(seconds: 15);

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _MockHttpClientRequest();

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _MockHttpClientRequest();

  @override
  void close({bool force = false}) {}
}

class _MockHttpClientRequest extends Fake implements HttpClientRequest {
  @override
  final HttpHeaders headers = _MockHttpHeaders();

  @override
  bool followRedirects = true;

  @override
  int maxRedirects = 5;

  @override
  int contentLength = 0;

  @override
  Future<HttpClientResponse> close() async => _MockHttpClientResponse();
}

class _MockHttpHeaders extends Fake implements HttpHeaders {
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}
}

class _MockHttpClientResponse extends Fake implements HttpClientResponse {
  @override
  int get statusCode => 200;

  @override
  int get contentLength => _fontBytes.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream.value(_fontBytes).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

class _MockHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _MockHttpClient();
}

Future<void> _captureRepaintKey(GlobalKey key, List<String> outputPaths) async {
  try {
    final boundary =
        key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) {
      debugPrint('Warning: Boundary is null');
      return;
    }
    final image = await boundary.toImage(pixelRatio: 2.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      debugPrint('Warning: ByteData is null');
      return;
    }
    final bytes = byteData.buffer.asUint8List();

    for (final path in outputPaths) {
      final f = File(path);
      await f.parent.create(recursive: true);
      await f.writeAsBytes(bytes);
      debugPrint('Saved screenshot: $path (${bytes.length} bytes)');
    }
  } catch (e, st) {
    debugPrint('Error saving screenshot: $e\n$st');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    _fontBytes = File('assets/fonts/JetBrainsMono-Medium.ttf').readAsBytesSync();
    HttpOverrides.global = _MockHttpOverrides();
    SharedPreferences.setMockInitialValues({});
  });

  tearDownAll(() {
    HttpOverrides.global = null;
  });

  testWidgets('Capture Quantum AI Agent Chat and History Sheet Screenshots', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2160);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);

    final tempDir = Directory.systemTemp.createTempSync('quantum_ai_snap_');
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    final runtime = RuntimeService();
    final settings = SettingsState(
      openrouterApiKey: 'demo-key',
    );

    final agent = QuantumAiAgentService(
      runtime,
      () => settings,
      () => tempDir.path,
    );

    // Create realistic sessions
    final now = DateTime.now();

    final session1 = ChatSession(
      id: 'session-adaptive-button',
      title: 'Адаптивная кнопка NeonButton',
      createdAt: now.subtract(const Duration(minutes: 25)),
      updatedAt: now.subtract(const Duration(minutes: 2)),
      modelId: 'openrouter/free',
      messages: [
        ChatMessage(
          id: 'm1',
          role: MessageRole.user,
          text:
              'Привет! Напиши адаптивную кнопку для Flutter с плавной анимацией нажатия и неоновым свечением.',
          timestamp: now.subtract(const Duration(minutes: 5)),
        ),
        ChatMessage(
          id: 'm2',
          role: MessageRole.assistant,
          thinking:
              'Анализ требований:\n1. Создать StatefulWidget с поддержкой AnimatedScale для физического эффекта нажатия.\n2. Использовать градиент Cyan-Purple (Material 3 Dark).\n3. Подготовить AgentAction (write_file) для автоматической вставки в проект.',
          text:
              'Конечно! Вот компонент **QuantumNeonButton** с плавной физической анимацией нажатия и неоновым свечением:\n\n'
              '```dart\n'
              'import \'package:flutter/material.dart\';\n\n'
              'class QuantumNeonButton extends StatefulWidget {\n'
              '  final String label;\n'
              '  final VoidCallback onPressed;\n\n'
              '  const QuantumNeonButton({\n'
              '    super.key,\n'
              '    required this.label,\n'
              '    required this.onPressed,\n'
              '  });\n\n'
              '  @override\n'
              '  State<QuantumNeonButton> createState() => _QuantumNeonButtonState();\n'
              '}\n\n'
              'class _QuantumNeonButtonState extends State<QuantumNeonButton> {\n'
              '  bool _pressed = false;\n\n'
              '  @override\n'
              '  Widget build(BuildContext context) {\n'
              '    return GestureDetector(\n'
              '      onTapDown: (_) => setState(() => _pressed = true),\n'
              '      onTapUp: (_) {\n'
              '        setState(() => _pressed = false);\n'
              '        widget.onPressed();\n'
              '      },\n'
              '      child: AnimatedScale(\n'
              '        scale: _pressed ? 0.95 : 1.0,\n'
              '        duration: const Duration(milliseconds: 120),\n'
              '        child: Container(\n'
              '          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),\n'
              '          decoration: BoxDecoration(\n'
              '            gradient: const LinearGradient(\n'
              '              colors: [Color(0xFF00E5FF), Color(0xFF7C3AED)],\n'
              '            ),\n'
              '            borderRadius: BorderRadius.circular(12),\n'
              '            boxShadow: [\n'
              '              BoxShadow(\n'
              '                color: const Color(0xFF00E5FF).withOpacity(_pressed ? 0.6 : 0.35),\n'
              '                blurRadius: _pressed ? 22 : 12,\n'
              '              ),\n'
              '            ],\n'
              '          ),\n'
              '          child: Text(\n'
              '            widget.label,\n'
              '            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),\n'
              '          ),\n'
              '        ),\n'
              '      ),\n'
              '    );\n'
              '  }\n'
              '}\n'
              '```\n\n'
              'Я также подготовил действие для записи файла в проект `lib/widgets/quantum_neon_button.dart`.',
          timestamp: now.subtract(const Duration(minutes: 4)),
          actions: [
            AgentAction(
              type: 'write_file',
              path: 'lib/widgets/quantum_neon_button.dart',
              content: '// QuantumNeonButton widget implementation',
            ),
          ],
        ),
      ],
    );

    final session2 = ChatSession(
      id: 'session-build-aab',
      title: 'Оптимизация сборки APK и AAB',
      createdAt: now.subtract(const Duration(days: 1, hours: 3)),
      updatedAt: now.subtract(const Duration(days: 1, minutes: 12)),
      modelId: 'openrouter/free',
      messages: [
        ChatMessage(
          id: 'm2_1',
          role: MessageRole.user,
          text: 'Как настроить gradle для сборки AAB без конфликтов ABI?',
          timestamp: now.subtract(const Duration(days: 1, hours: 3)),
        ),
      ],
    );

    final session3 = ChatSession(
      id: 'session-mcp-tools',
      title: 'Интеграция Model Context Protocol (MCP)',
      createdAt: now.subtract(const Duration(days: 3)),
      updatedAt: now.subtract(const Duration(days: 2, hours: 5)),
      modelId: 'openrouter/free',
      messages: [
        ChatMessage(
          id: 'm3_1',
          role: MessageRole.user,
          text: 'Подключи MCP сервер файловой системы и GitHub',
          timestamp: now.subtract(const Duration(days: 3)),
        ),
      ],
    );

    final session4 = ChatSession(
      id: 'session-dark-md',
      title: 'Исправление темной темы Markdown',
      createdAt: now.subtract(const Duration(days: 5)),
      updatedAt: now.subtract(const Duration(days: 4)),
      modelId: 'openrouter/free',
      messages: [
        ChatMessage(
          id: 'm4_1',
          role: MessageRole.user,
          text: 'Текст в файлах .md отображался черным на черном фоне.',
          timestamp: now.subtract(const Duration(days: 5)),
        ),
      ],
    );

    agent.setSessionsForTesting([session1, session2, session3, session4]);
    agent.setCurrentSessionForTesting(session1);

    final repaintKey = GlobalKey();

    final testWidget = ProviderScope(
      overrides: [
        quantumAiAgentServiceProvider.overrideWith((ref) => agent),
        settingsProvider.overrideWith((ref) {
          final s = SettingsService();
          s.state = settings;
          return s;
        }),
        workspaceProvider.overrideWith(
          (ref) => WorkspaceNotifier(ref)
            ..setWorkspace('/root/projects/quantum_ide'),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.dark,
        theme: ThemeData.dark(useMaterial3: true).copyWith(
          scaffoldBackgroundColor: const Color(0xFF0F1013),
        ),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('ru'), Locale('en')],
        locale: const Locale('ru'),
        builder: (context, child) => RepaintBoundary(
          key: repaintKey,
          child: child ?? const SizedBox.shrink(),
        ),
        home: const Scaffold(
          body: QuantumAiAgentPanel(isExpanded: true),
        ),
      ),
    );

    await tester.pumpWidget(testWidget);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));

    // 1. Capture Main AI Agent Chat View
    const artifactDir =
        '/root/.gemini/antigravity-cli/brain/d2c6c5a1-76e7-4c96-9658-7bf9c4ea481f';
    final chat1Paths = [
      '$artifactDir/01_ai_agent_chat_main.png',
      '/root/projects/quantum_ide/.quantum/screenshots/01_ai_agent_chat_main.png',
      '/root/projects/quantum_ide/foto/01_ai_agent_chat_main.png',
    ];

    await tester.runAsync(() async {
      await _captureRepaintKey(repaintKey, chat1Paths);
    });

    // 2. Open Chat History Sheet
    final historyBtn = find.byIcon(LucideIcons.history);
    expect(historyBtn, findsOneWidget);
    await tester.tap(historyBtn);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 500));

    // Capture Chat History Sheet View
    final chat2Paths = [
      '$artifactDir/02_ai_agent_chat_history.png',
      '/root/projects/quantum_ide/.quantum/screenshots/02_ai_agent_chat_history.png',
      '/root/projects/quantum_ide/foto/02_ai_agent_chat_history.png',
    ];

    await tester.runAsync(() async {
      await _captureRepaintKey(repaintKey, chat2Paths);
    });

    await tester.pump(const Duration(seconds: 15));
  });
}
